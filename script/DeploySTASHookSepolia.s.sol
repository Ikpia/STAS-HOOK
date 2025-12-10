// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {STASHook} from "../src/STASHook.sol";
import {PythOracleAdapter} from "../src/PythOracleAdapter.sol";

/// @notice Deploy STASHook to Sepolia using env-provided values.
/// @dev Requires the CREATE2 factory (0x4e59...) to be funded on Sepolia.
contract DeploySTASHookSepolia is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        address poolManager = vm.envAddress("POOL_MANAGER_ADDRESS");
        address pyth = vm.envAddress("PYTH_ADDRESS");
        bytes32 priceFeedId0 = vm.envBytes32("PRICE_FEED_ID0");
        bytes32 priceFeedId1 = vm.envBytes32("PRICE_FEED_ID1");
        address reserveToken = vm.envAddress("RESERVE_TOKEN");
        address admin = vm.envOr("ADMIN_ADDRESS", vm.addr(deployerKey));

        uint160 flags = Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG;

        vm.startBroadcast(deployerKey);

        PythOracleAdapter adapter = new PythOracleAdapter(pyth);

        bytes memory ctorArgs =
            abi.encode(poolManager, address(adapter), priceFeedId0, priceFeedId1, reserveToken, admin);
        (address expectedHook, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(STASHook).creationCode, ctorArgs);

        STASHook hook = new STASHook{salt: salt}(
            IPoolManager(poolManager), address(adapter), priceFeedId0, priceFeedId1, reserveToken, admin
        );

        vm.stopBroadcast();

        require(address(hook) == expectedHook, "DeploySTASHookSepolia: hook addr mismatch");

        console2.log("Adapter deployed:", address(adapter));
        console2.log("Hook deployed:", address(hook));
        console2.log("Salt used (bytes32):");
        console2.logBytes32(salt);
    }
}

