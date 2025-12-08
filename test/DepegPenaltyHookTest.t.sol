// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {STASHook} from "../src/STASHook.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {PythOracleAdapter} from "../src/PythOracleAdapter.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";

contract STASHookTest is Test {
    using PoolIdLibrary for PoolKey;
    using LPFeeLibrary for uint24;
    using CurrencyLibrary for Currency;

    STASHook public hook;
    PythOracleAdapter public pythAdapter;

    MockERC20 mockUSDC;
    MockERC20 mockUSDT;

    PoolKey public poolKey;
    PoolId public poolId;
    address public user = makeAddr("user");
    address public swapper = makeAddr("swapper");
    address public reserveToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC

    // Real mainnet addresses (Sep 2025)
    address constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address constant UNIVERSAL_ROUTER = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address constant PYTH = 0xeFc0CED4B3D536103e76a1c4c74F0385C8F4Bdd3;

    // Test pool: USDC/USDT (1:1 peg example)
    address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    Currency public usdt ;
    Currency public usdc ;
    bytes32 constant USDC_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a; // USDC/USD
    bytes32 constant USDT_ID = 0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b; // USDT/USD

    IPoolManager public poolManager = IPoolManager(POOL_MANAGER);
    IUniversalRouter public universalRouter = IUniversalRouter(payable(0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af));

    uint24 public constant BASE_FEE = 3000; // 0.3%
    int24 public constant TICK_SPACING = 10; // For stable pairs
    uint160 public constant FLAGS = Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG;
    address USDT_WHALE = 0xF977814e90dA44bFA03b6295A0616a897441aceC;


    function setUp() public {
        // Deploy mocks instead of real tokens
        mockUSDC = new MockERC20("USD Coin", "USDC");
        mockUSDT = new MockERC20("Tether USD", "USDT");

        USDC = address(mockUSDC);
        USDT = address(mockUSDT);

        usdt = Currency.wrap(USDT);
        usdc = Currency.wrap(USDC);

        // Deploy real adapters and hook
        pythAdapter = new PythOracleAdapter(PYTH); // Dual feeds for USDC/USDT

        // Mine and deploy hook with correct flags
        bytes memory constructorArgs =
            abi.encode(POOL_MANAGER, address(pythAdapter), USDC_ID, USDT_ID, reserveToken, user);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, FLAGS, type(DepegPenaltyHook).creationCode, constructorArgs);

        console.logBytes(constructorArgs);
        console.log(hookAddress);
        console.logBytes32(salt);

        // Deploy via CREATE2 deployer
        vm.broadcast();
        (bool success,) =
            CREATE2_DEPLOYER.call(abi.encodePacked(salt, type(DepegPenaltyHook).creationCode, constructorArgs));
        require(success, "Deployment failed");
        hook = DepegPenaltyHook(hookAddress);
        // vm.broadcast();
        // DepegPenaltyHook pointsHook = new DepegPenaltyHook{salt: salt}(IPoolManager(POOL_MANAGER), address(pythAdapter), USDC_ID, USDT_ID, reserveToken, user);
        // console.log(address(pointsHook));
        // require(address(pointsHook) == hookAddress, "PointsHookScript: hook address mismatch");
        require(address(hook) == hookAddress, "Hook address mismatch");

        // Create pool (USDC/USDT, dynamic fee)
        poolKey = PoolKey({
            currency0: address(mockUSDC )< address(mockUSDT) ? Currency.wrap(address(mockUSDC)) : Currency.wrap(address(mockUSDT)),
            currency1: address(mockUSDC )< address(mockUSDT) ? Currency.wrap(address(mockUSDT)) : Currency.wrap(address(mockUSDC)),
            fee: BASE_FEE,
            tickSpacing: TICK_SPACING,
            hooks: hook
        });
        poolId = poolKey.toId();

        // Initialize pool at 1:1 price
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0); // 1:1
        vm.prank(user);
        poolManager.initialize(poolKey, sqrtPriceX96);

        // Fund swapper
        deal(address(mockUSDC), swapper, 1000000 * 1e6); // 1M USDC (6 decimals)
        deal(USDT, swapper, 1000000 * 1e6); // 1M USDT
        vm.startPrank(swapper);
        IERC20(USDC).approve(PERMIT2, type(uint256).max);
        IERC20(USDT).approve(PERMIT2, type(uint256).max);
        IAllowanceTransfer(PERMIT2).approve(USDC, UNIVERSAL_ROUTER, type(uint160).max, type(uint48).max);
        IAllowanceTransfer(PERMIT2).approve(USDT, UNIVERSAL_ROUTER, type(uint160).max, type(uint48).max);
        vm.stopPrank();

        // Fund hook reserve for rebates
        deal(reserveToken, address(hook), 1000 * 1e6); // 1k USDC
    }

    // function initializePool(uint160 sqrtPriceX96) internal {
    //     bytes memory initCall = abi.encodeWithSelector(IPoolInitializer.initializePool.selector, poolKey, sqrtPriceX96);

    //     bytes[] memory calls = new bytes[](1);
    //     calls[0] = initCall;

    //     vm.prank(user);
    //     console.log("vfjhvjhf ");
    //     IPoolInitializer(POSITION_MANAGER).multicall(calls);
    // }

    function performSwap(bool zeroForOne, uint256 amountIn) internal {
        // vm.prank(swapper);

        PoolKey memory poolKeyMem = PoolKey({
            currency0: poolKey.currency0,
            currency1: poolKey.currency1,
            fee: BASE_FEE,
            tickSpacing: TICK_SPACING,
            hooks: hook
        });

        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKeyMem,
                zeroForOne: zeroForOne,
                amountIn: uint128(amountIn),
                amountOutMinimum: 0,
                hookData: new bytes(0)
            })
        );
        params[1] = abi.encode(zeroForOne ? poolKey.currency0 : poolKey.currency1, amountIn);
        params[2] = abi.encode(zeroForOne ? poolKey.currency1 : poolKey.currency0, 0);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        universalRouter.execute(commands, inputs, block.timestamp + 30);
    }

    function test_PenalizeWideningDepeg() public {
        // Mock Pyth: USDC = $0.99, USDT = $1.00 (1% depeg), conf = 0.01
        vm.mockCall(
            address(pythAdapter),
            abi.encodeWithSelector(PythOracleAdapter.getPriceWithConfidence.selector, USDC_ID),
            abi.encode(9900, 10, block.timestamp) // 0.99 USD
        );
        vm.mockCall(
            address(pythAdapter),
            abi.encodeWithSelector(PythOracleAdapter.getPriceWithConfidence.selector, USDT_ID),
            abi.encode(10000, 10, block.timestamp) // 1.00 USD
        );

        // Swap USDC -> USDT (worsens depeg, zeroForOne = true)
        uint256 amountIn = 10000 * 1e6; // 10k USDC
        vm.prank(swapper);
        performSwap(true, amountIn); // zeroForOne = true
    }

    function test_RewardStabilizingDepeg() public {
        // Mock Pyth: USDC = $0.99, USDT = $1.00 (1% depeg), conf = 0.01
        vm.mockCall(
            address(pythAdapter),
            abi.encodeWithSelector(PythOracleAdapter.getPriceWithConfidence.selector, USDC_ID),
            abi.encode(9900, 10, block.timestamp) // 0.99 USD
        );
        vm.mockCall(
            address(pythAdapter),
            abi.encodeWithSelector(PythOracleAdapter.getPriceWithConfidence.selector, USDT_ID),
            abi.encode(10000, 10, block.timestamp) // 1.00 USD
        );

        // Swap USDT -> USDC (narrows depeg, buys USDC)
        uint256 amountIn = 10000 * 1e6; // 10k USDT
        vm.prank(swapper);
        vm.expectEmit(true, true, true, true);
        // emit DepegRebateIssued(poolId, swapper, 50 * 1e6); // 50 USDC rebate
        performSwap(true, amountIn); // zeroForOne = true
    }

    function test_NoOverrideHighConfidence() public {
        // Mock Pyth with high conf (volatile, no override)
        vm.mockCall(
            address(pythAdapter),
            abi.encodeWithSelector(PythOracleAdapter.getPriceWithConfidence.selector, USDC_ID),
            abi.encode(10000, 1000, block.timestamp) // High conf (10%)
        );
        vm.mockCall(
            address(pythAdapter),
            abi.encodeWithSelector(PythOracleAdapter.getPriceWithConfidence.selector, USDT_ID),
            abi.encode(10000, 1000, block.timestamp) // High conf
        );

        // Swap should use base fee (0.3%)
        uint256 amountIn = 10000 * 1e6; // 10k USDC
        vm.prank(swapper);
        // Expect base fee, no penalty event
        performSwap(true, amountIn); // zeroForOne = true
    }

    function test_BaseFeeNoDepeg() public {
        // Mock Pyth with 1:1 peg (no depeg, base fee)
        vm.mockCall(
            address(pythAdapter),
            abi.encodeWithSelector(PythOracleAdapter.getPriceWithConfidence.selector, USDC_ID),
            abi.encode(10000, 10, block.timestamp) // $1.00
        );
        vm.mockCall(
            address(pythAdapter),
            abi.encodeWithSelector(PythOracleAdapter.getPriceWithConfidence.selector, USDT_ID),
            abi.encode(10000, 10, block.timestamp) // $1.00
        );

        // Swap should use base fee
        uint256 amountIn = 10000 * 1e6; // 10k USDC
        vm.prank(swapper);
        // Expect base fee, no penalty event
        performSwap(true, amountIn); // zeroForOne = true
    }
}

