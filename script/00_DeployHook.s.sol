// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {BaseScript} from "./base/BaseScript.sol";
import {STASHook} from "../src/STASHook.sol";
import {PythOracleAdapter} from "../src/PythOracleAdapter.sol";

/// @notice Mines the address and deploys the STASHook contract
contract DeployHookScript is BaseScript {
    // Mainnet-like constants (matches test setup); replace as needed
    address constant PYTH = 0xeFc0CED4B3D536103e76a1c4c74F0385C8F4Bdd3;
    bytes32 constant USDC_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    bytes32 constant USDT_ID = 0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b;
    address constant RESERVE_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    uint160 constant FLAGS = Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG;

    function run() public {
        // Deploy adapter
        vm.startBroadcast();
        PythOracleAdapter adapter = new PythOracleAdapter(PYTH);

        // Mine salt for the hook
        bytes memory constructorArgs =
            abi.encode(poolManager, address(adapter), USDC_ID, USDT_ID, RESERVE_TOKEN, msg.sender);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, FLAGS, type(STASHook).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        STASHook hook = new STASHook{salt: salt}(poolManager, address(adapter), USDC_ID, USDT_ID, RESERVE_TOKEN, msg.sender);
        vm.stopBroadcast();

        require(address(hook) == hookAddress, "DeployHookScript: Hook Address Mismatch");
    }
}
