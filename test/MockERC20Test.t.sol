// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract MockERC20Test is Test {
    function test_mint_increases_balance_and_supply() public {
        MockERC20 token = new MockERC20("Mock", "MOCK");
        token.mint(address(this), 1_000);
        assertEq(token.balanceOf(address(this)), 1_000);
        assertEq(token.totalSupply(), 1_000);
    }
}


