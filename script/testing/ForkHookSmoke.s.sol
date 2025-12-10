// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {STASHook} from "../../src/STASHook.sol";
import {PythOracleAdapter} from "../../src/PythOracleAdapter.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @dev Minimal harness to expose internal STASHook calls for scripting.
/// @notice This bypasses address validation for fork testing purposes.
contract STASHookForkHarness {
    using PoolIdLibrary for PoolKey;
    
    // Copy the essential state from STASHook
    PythOracleAdapter public immutable pythAdapter;
    bytes32 public immutable priceFeedId0;
    bytes32 public immutable priceFeedId1;
    address public immutable reserveToken;
    mapping(PoolId => STASHook.PoolState) public poolStates;
    
    constructor(
        address _pythAdapter,
        bytes32 _priceFeedId0,
        bytes32 _priceFeedId1,
        address _reserveToken,
        address _admin
    ) {
        pythAdapter = PythOracleAdapter(_pythAdapter);
        priceFeedId0 = _priceFeedId0;
        priceFeedId1 = _priceFeedId1;
        reserveToken = _reserveToken;
        // Note: We skip access control setup for fork testing
    }

    function callAfterInit(PoolKey calldata key, uint160 sqrtPriceX96, int24 tick) external returns (bytes4) {
        PoolId poolId = key.toId();
        poolStates[poolId].baseFee = key.fee;
        poolStates[poolId].lastDepegBps = 0;
        return this.callAfterInit.selector;
    }

    function callGetFee(PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external
        view
        returns (uint24)
    {
        PoolId poolId = key.toId();
        STASHook.PoolState storage state = poolStates[poolId];

        (int64 price0, uint64 conf0,) = pythAdapter.getPriceWithConfidence(priceFeedId0);
        (int64 price1, uint64 conf1,) = pythAdapter.getPriceWithConfidence(priceFeedId1);
        uint256 confRatioBps =
            (pythAdapter.computeConfRatioBps(price0, conf0) + pythAdapter.computeConfRatioBps(price1, conf1)) / 2;
        if (confRatioBps > 100) return state.baseFee; // VOLATILE_THRESHOLD

        int64 depegDiff = price0 > price1 ? price0 - price1 : price1 - price0;
        uint256 depegBps = (uint256(depegDiff >= 0 ? int256(depegDiff) : int256(-depegDiff))) * 10000
            / (price1 > 0 ? uint256(uint64(price1)) : 1);

        bool worsensDepeg = (price0 < price1 && params.zeroForOne) || (price0 > price1 && !params.zeroForOne);

        if (worsensDepeg && depegBps > 50) { // DEPEG_THRESHOLD
            uint24 fee = state.baseFee + uint24(depegBps / 10 * 100);
            return fee > 50000 ? 50000 : fee; // MAX_PENALTY_FEE
        } else if (!worsensDepeg && depegBps > 50) {
            uint24 fee = 1000 - uint24(depegBps / 20 * 50);
            return fee < 500 ? 500 : fee; // MIN_STABILIZE_FEE
        }
        return state.baseFee;
    }
}

/// @notice Runs a forked smoke test (no broadcast) to validate the hook logic end-to-end.
/// @dev Expects MAINNET_RPC_URL (and optional MAINNET_FORK_BLOCK) to be set. Also uses PYTH_ADDRESS, PRICE_FEED_ID0/1, RESERVE_TOKEN.
contract ForkHookSmoke is Script {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    bytes32 constant USDC_ID_DEFAULT =
        0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    bytes32 constant USDT_ID_DEFAULT =
        0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b;

    function run() external {
        // Fork mainnet (or the provided chain)
        string memory rpcUrl = vm.envString("MAINNET_RPC_URL");
        uint256 blockNumber = vm.envOr("MAINNET_FORK_BLOCK", uint256(0));
        if (blockNumber != 0) {
            vm.createSelectFork(rpcUrl, blockNumber);
        } else {
            vm.createSelectFork(rpcUrl);
        }

        // Inputs (use env overrides where provided)
        address pyth = vm.envAddress("PYTH_ADDRESS");
        bytes32 feed0 = vm.envOr("PRICE_FEED_ID0", USDC_ID_DEFAULT);
        bytes32 feed1 = vm.envOr("PRICE_FEED_ID1", USDT_ID_DEFAULT);
        address reserveToken = vm.envAddress("RESERVE_TOKEN");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envOr("ADMIN_ADDRESS", vm.addr(deployerKey));

        // Deploy adapter and hook harness (no broadcast)
        PythOracleAdapter adapter = new PythOracleAdapter(pyth);
        STASHookForkHarness hook = new STASHookForkHarness(address(adapter), feed0, feed1, reserveToken, admin);

        // Local tokens & pool key
        MockERC20 t0 = new MockERC20("ForkUSD0", "FUSD0");
        MockERC20 t1 = new MockERC20("ForkUSD1", "FUSD1");
        Currency c0 = Currency.wrap(address(t0));
        Currency c1 = Currency.wrap(address(t1));
        PoolKey memory poolKey = PoolKey({
            currency0: address(t0) < address(t1) ? c0 : c1,
            currency1: address(t0) < address(t1) ? c1 : c0,
            fee: 3000,
            tickSpacing: 10,
            hooks: IHooks(address(hook))
        });

        hook.callAfterInit(poolKey, TickMath.getSqrtPriceAtTick(0), 0);

        // Mock Pyth responses
        _mockPrice(address(adapter), feed0, 9900, 10);
        _mockPrice(address(adapter), feed1, 10000, 10);

        // Compute fees
        uint24 feeWorsen = _fee(hook, poolKey, true);
        uint24 feeStabilize = _fee(hook, poolKey, false);

        console2.log("Fork smoke fee (worsen):", feeWorsen);
        console2.log("Fork smoke fee (stabilize):", feeStabilize);

        // Basic expectations (mirrors README logic)
        require(feeWorsen > 3000, "worsening trade should pay penalty");
        require(feeStabilize < 3000, "stabilizing trade should get rebate");
    }

    function _fee(STASHookForkHarness hook, PoolKey memory key, bool zeroForOne) internal view returns (uint24) {
        SwapParams memory params = SwapParams({zeroForOne: zeroForOne, amountSpecified: 1, sqrtPriceLimitX96: 0});
        return hook.callGetFee(key, params, "");
    }

    function _mockPrice(address adapter, bytes32 id, int64 price, uint64 conf) internal {
        vm.mockCall(
            adapter, abi.encodeWithSelector(PythOracleAdapter.getPriceWithConfidence.selector, id), abi.encode(price, conf, block.timestamp)
        );
    }
}

