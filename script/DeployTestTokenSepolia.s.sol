// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/// @notice Deploys a test ERC20 token on Sepolia for use as reserve token
contract DeployTestTokenSepolia is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy test token
        MockERC20 token = new MockERC20("STAS Reserve Token", "STRT");

        // Mint some tokens to the deployer for testing
        token.mint(deployer, 1_000_000 * 10 ** 18);

        vm.stopBroadcast();

        console2.log("Test Token deployed at:", address(token));
        console2.log("Token name:", token.name());
        console2.log("Token symbol:", token.symbol());
        console2.log("Deployer balance:", token.balanceOf(deployer));
    }
}

