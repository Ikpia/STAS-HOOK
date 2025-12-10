// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {PythOracleAdapter} from "../src/PythOracleAdapter.sol";
import {IPyth} from "@pythnetwork/IPyth.sol";
import {PythStructs} from "@pythnetwork/PythStructs.sol";

contract PythOracleAdapterTest is Test {
    address constant PYTH = address(0xBEEF);
    bytes32 constant FEED = bytes32(uint256(1));

    function test_constructor_reverts_on_zero() public {
        vm.expectRevert("PythOracleAdapter: zero address");
        new PythOracleAdapter(address(0));
    }

    function test_getPriceWithConfidence_reads_pyth() public {
        PythOracleAdapter adapter = new PythOracleAdapter(PYTH);
        PythStructs.Price memory p = PythStructs.Price({price: 12345, conf: 77, expo: 0, publishTime: 999});
        vm.mockCall(
            PYTH,
            abi.encodeWithSelector(IPyth.getPriceUnsafe.selector, FEED),
            abi.encode(p)
        );
        (int64 price, uint64 conf, uint256 ts) = adapter.getPriceWithConfidence(FEED);
        assertEq(price, 12345);
        assertEq(conf, 77);
        assertEq(ts, 999);
    }

    function test_computeConfRatioBps_handles_zero_price() public {
        uint256 ratio = PythOracleAdapter(address(new PythOracleAdapter(PYTH))).computeConfRatioBps(0, 100);
        assertEq(ratio, 0);
    }

    function test_computeConfRatioBps_positive_and_negative() public {
        PythOracleAdapter adapter = new PythOracleAdapter(PYTH);
        uint256 ratioPos = adapter.computeConfRatioBps(10_000, 100); // 1%
        uint256 ratioNeg = adapter.computeConfRatioBps(-10_000, 100);
        assertEq(ratioPos, ratioNeg);
        assertEq(ratioPos, 100); // 1% * 10000 / 10000
    }

    function test_setMaxStaleness() public {
        PythOracleAdapter adapter = new PythOracleAdapter(PYTH);
        adapter.setMaxStaleness(123);
        assertEq(adapter.maxStaleness(), 123);
        vm.expectRevert("PythOracleAdapter: invalid staleness");
        adapter.setMaxStaleness(0);
    }
}

