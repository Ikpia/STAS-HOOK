// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {PythOracleAdapter} from "./PythOracleAdapter.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {Position} from "@uniswap/v4-core/src/libraries/Position.sol";
import {TickBitmap} from "@uniswap/v4-core/src/libraries/TickBitmap.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {BitMath} from "@uniswap/v4-core/src/libraries/BitMath.sol";
import {BaseOverrideFee} from "@uniswap/hooks/fee/BaseOverrideFee.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

interface IMsgSender {
    function msgSender() external view returns (address);
}

/// @title DepegPenaltyHook
/// @notice Uniswap V4 hook that stabilizes 1:1 pegs using Pyth oracles.
/// @dev Penalizes trades that widen the peg and rewards those that restore it.
/// This hook implements dynamic fee adjustment based on real-time oracle price feeds
/// to maintain stablecoin pool stability during market stress events.
contract DepegPenaltyHook is BaseOverrideFee, AccessControl {
    using PoolIdLibrary for PoolKey;
    using LPFeeLibrary for uint24;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG_ROLE");

    struct PoolState {
        uint24 baseFee; // Default fee (e.g., 3000 for 0.3%)
        uint256 lastDepegBps; // Last depeg ratio in basis points
        uint256 reserveBalance; // Hook reserve in reserveToken
        uint256 totalPenaltyFees; // Accumulated penalty fees
    }

    mapping(PoolId => PoolState) public poolStates;
    PythOracleAdapter public immutable pythAdapter;
    bytes32 public immutable priceFeedId0; // Pyth feed for token0 (e.g., kHYPE)
    bytes32 public immutable priceFeedId1; // Pyth feed for token1 (e.g., HYPE)
    address public immutable reserveToken; // Token for penalties/rebates (e.g., USDC or BONUS)
    uint256 public constant VOLATILE_THRESHOLD = 100; // 1% confidence threshold
    uint256 public constant DEPEG_THRESHOLD = 50; // 0.5% depeg threshold
    uint24 public constant MAX_PENALTY_FEE = 50000; // 5%
    uint24 public constant MIN_STABILIZE_FEE = 500; // 0.05%
    uint256 public constant MIN_RESERVE_CUT_BPS = 2000; // 20%
    uint256 public constant MAX_RESERVE_CUT_BPS = 5000; // 50%
    uint256 public constant MIN_REBATE_BPS = 500; // 0.05%
    uint256 public constant REBATE_SCALE_BPS = 10; // 0.001% per 10 bps reduction
    bool public paused;

    event DepegPenaltyApplied(PoolId indexed poolId, bool zeroForOne, uint24 fee, uint256 reserveAmount);
    event DepegRebateIssued(PoolId indexed poolId, address trader, uint256 amount);
    event TargetRange(PoolId indexed poolId, int24 tickLower, int24 tickUpper);

    constructor(
        IPoolManager _poolManager,
        address _pythAdapter,
        bytes32 _priceFeedId0,
        bytes32 _priceFeedId1,
        address _reserveToken,
        address _admin
    ) BaseOverrideFee(_poolManager) {
        pythAdapter = PythOracleAdapter(_pythAdapter);
        priceFeedId0 = _priceFeedId0;
        priceFeedId1 = _priceFeedId1;
        reserveToken = _reserveToken;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _grantRole(CONFIG_ROLE, _admin);
    }

    /// @dev Modifier to check if not paused
    modifier whenNotPaused() {
        require(!paused, "DepegPenaltyHook: paused");
        _;
    }

    function _afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick)
        internal
        override
        returns (bytes4)
    {
        PoolId poolId = key.toId();
        poolStates[poolId].baseFee = key.fee;
        poolStates[poolId].lastDepegBps = 0;
        emit TargetRange(poolId, -60, 60);
        return this.afterInitialize.selector;
    }

    function _getFee(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        view
        override
        returns (uint24)
    {
        PoolId poolId = key.toId();
        PoolState storage state = poolStates[poolId];

        (int64 price0, uint64 conf0,) = pythAdapter.getPriceWithConfidence(priceFeedId0);
        (int64 price1, uint64 conf1,) = pythAdapter.getPriceWithConfidence(priceFeedId1);
        uint256 confRatioBps =
            (pythAdapter.computeConfRatioBps(price0, conf0) + pythAdapter.computeConfRatioBps(price1, conf1)) / 2;
        if (confRatioBps > VOLATILE_THRESHOLD) return state.baseFee;

        // console.log(price0);
        // console.log(price1);
        // console.log(confRatioBps);

        // Compute depeg: |price0 - price1| / price1 * 10000
        int64 depegDiff = price0 > price1 ? price0 - price1 : price1 - price0;
        uint256 depegBps = (uint256(depegDiff >= 0 ? int256(depegDiff) : int256(-depegDiff))) * 10000
            / (price1 > 0 ? uint256(uint64(price1)) : 1);
        // console.log(depegDiff);
        // console.log(depegBps);

        bool worsensDepeg = (price0 < price1 && params.zeroForOne) || (price0 > price1 && !params.zeroForOne);
        // console.log(worsensDepeg);

        if (worsensDepeg && depegBps > DEPEG_THRESHOLD) {
            uint24 fee = state.baseFee + uint24(depegBps / 10 * 100);
            // console.log(fee);
            // console.log(state.baseFee);
            // console.log(depegBps);
            return fee > MAX_PENALTY_FEE ? MAX_PENALTY_FEE : fee;
        } else if (!worsensDepeg && depegBps > DEPEG_THRESHOLD) {
            uint24 fee = 1000 - uint24(depegBps / 20 * 50);
            return fee < MIN_STABILIZE_FEE ? MIN_STABILIZE_FEE : fee;
        }
        return state.baseFee;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory permissions) {
        permissions = super.getHookPermissions();
        return permissions;
    }
}

