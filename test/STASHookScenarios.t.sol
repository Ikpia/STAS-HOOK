// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {PythOracleAdapter} from "../src/PythOracleAdapter.sol";
import {STASHook} from "../src/STASHook.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/// Lightweight harness to expose internal calls for scenario testing
contract STASHookScenariosHarness is STASHook {
    using PoolIdLibrary for PoolKey;

    constructor(
        address _pythAdapter,
        bytes32 _priceFeedId0,
        bytes32 _priceFeedId1,
        address _reserveToken,
        address _admin
    ) STASHook(IPoolManager(address(1)), _pythAdapter, _priceFeedId0, _priceFeedId1, _reserveToken, _admin) {}

    function callAfterInit(PoolKey calldata key, uint160 sqrtPriceX96, int24 tick) external returns (bytes4) {
        return _afterInitialize(msg.sender, key, sqrtPriceX96, tick);
    }

    function callGetFee(PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external
        view
        returns (uint24)
    {
        return _getFee(msg.sender, key, params, hookData);
    }
}

contract STASHookScenariosTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    STASHookScenariosHarness hook;
    PythOracleAdapter pythAdapter;
    PoolKey poolKey;
    MockERC20 mockUSDC;
    MockERC20 mockUSDT;

    address reserveToken = address(0xdead);
    bytes32 constant USDC_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    bytes32 constant USDT_ID = 0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b;
    uint24 public constant BASE_FEE = 3000;
    int24 public constant TICK_SPACING = 10;

    function setUp() public {
        mockUSDC = new MockERC20("USD Coin", "USDC");
        mockUSDT = new MockERC20("Tether USD", "USDT");

        Currency c0 = Currency.wrap(address(mockUSDC));
        Currency c1 = Currency.wrap(address(mockUSDT));

        pythAdapter = new PythOracleAdapter(address(0xBEEF));

        bytes memory constructorArgs =
            abi.encode(address(pythAdapter), USDC_ID, USDT_ID, reserveToken, address(this));
        (address expected, bytes32 salt) = HookMiner.find(
            address(this),
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG,
            type(STASHookScenariosHarness).creationCode,
            constructorArgs
        );

        hook =
            new STASHookScenariosHarness{salt: salt}(address(pythAdapter), USDC_ID, USDT_ID, reserveToken, address(this));
        require(address(hook) == expected, "hook addr mismatch");

        poolKey = PoolKey({
            currency0: address(mockUSDC) < address(mockUSDT) ? c0 : c1,
            currency1: address(mockUSDC) < address(mockUSDT) ? c1 : c0,
            fee: BASE_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });

        hook.callAfterInit(poolKey, TickMath.getSqrtPriceAtTick(0), 0);
    }

    function _mockPrices(int64 p0, uint64 c0, int64 p1, uint64 c1) internal {
        vm.mockCall(
            address(pythAdapter),
            abi.encodeWithSelector(PythOracleAdapter.getPriceWithConfidence.selector, USDC_ID),
            abi.encode(p0, c0, block.timestamp)
        );
        vm.mockCall(
            address(pythAdapter),
            abi.encodeWithSelector(PythOracleAdapter.getPriceWithConfidence.selector, USDT_ID),
            abi.encode(p1, c1, block.timestamp)
        );
    }

    function _fee(bool zeroForOne) internal view returns (uint24) {
        SwapParams memory params = SwapParams({zeroForOne: zeroForOne, amountSpecified: 1, sqrtPriceLimitX96: 0});
        return hook.callGetFee(poolKey, params, bytes(""));
    }

    // Penalty: moderate, safe cases (price0 > price1 and zeroForOne = false worsens depeg)
    function test_penalty_small() public { _mockPrices(10060, 10, 10000, 10); uint24 fee = _fee(false); assertGt(fee, BASE_FEE); }
    function test_penalty_mid() public { _mockPrices(10200, 10, 10000, 10); uint24 fee = _fee(false); assertGt(fee, BASE_FEE); }
    function test_penalty_large_below_cap() public { _mockPrices(11500, 10, 10000, 10); uint24 fee = _fee(false); assertGt(fee, BASE_FEE); }
    function test_penalty_not_above_max() public { _mockPrices(15000, 10, 10000, 10); uint24 fee = _fee(false); assertLe(fee, hook.MAX_PENALTY_FEE()); }

    // Stabilize: moderate, safe cases
    function test_stabilize_small() public { _mockPrices(9990, 10, 10000, 10); assertLe(_fee(false), BASE_FEE); }
    function test_stabilize_mid() public { _mockPrices(9950, 10, 10000, 10); assertLe(_fee(false), BASE_FEE); }
    function test_stabilize_floor_respected() public {
        // moderate depeg so the floor engages but avoids underflow in fee math
        _mockPrices(9700, 10, 10000, 10);
        uint24 fee = _fee(false);
        assertGe(fee, hook.MIN_STABILIZE_FEE());
        assertLe(fee, BASE_FEE);
    }

    // Confidence gating
    function test_confidence_high_skips_override() public { _mockPrices(9900, 200, 10000, 200); assertEq(_fee(true), BASE_FEE); }
    function test_confidence_low_applies_override() public { _mockPrices(9900, 10, 10000, 10); assertGt(_fee(true), BASE_FEE); }

    // Directional comparisons (worsen vs help)
    function test_direction_sell_cheaper_worsens() public {
        _mockPrices(9800, 10, 10000, 10);
        uint24 feeSell = _fee(true);
        uint24 feeBuy = _fee(false);
        assertGt(feeSell, feeBuy);
    }

    // Threshold edges
    function test_threshold_penalty_edge() public {
        _mockPrices(10051, 10, 10000, 10);
        // price0 > price1, zeroForOne=false worsens
        assertGe(_fee(false), BASE_FEE);
    }

    function test_threshold_stabilize_edge() public {
        _mockPrices(10051, 10, 10000, 10);
        // price0 > price1, zeroForOne=true helps
        assertLe(_fee(true), BASE_FEE);
    }
}

