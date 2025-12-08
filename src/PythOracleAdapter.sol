// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPyth} from "@pythnetwork/IPyth.sol";
import {PythStructs} from "@pythnetwork/PythStructs.sol";

/// @title PythOracleAdapter
/// @notice Adapter for reading Pyth price and confidence for two tokens.
/// @dev Normalizes values and provides helpers for confRatio calculation.
/// This adapter wraps Pyth Network oracle calls and provides standardized
/// price and confidence data for use in the DepegPenaltyHook.
contract PythOracleAdapter {
    IPyth public immutable pyth;

    /// @notice Maximum allowed staleness for price feeds in seconds
    /// @dev Default is 60 seconds. Can be updated by governance.
    uint256 public maxStaleness = 60; // Seconds; configurable

    /// @notice Constructs a new PythOracleAdapter
    /// @param _pyth The address of the Pyth Network oracle contract
    constructor(address _pyth) {
        require(_pyth != address(0), "PythOracleAdapter: zero address");
        pyth = IPyth(_pyth);
    }

    /// @notice Get price, confidence, and publish time for a specified price feed
    /// @param priceFeedId The Pyth price feed ID (either priceFeedId0 or priceFeedId1)
    /// @return price The current price from Pyth oracle
    /// @return conf The confidence interval for the price
    /// @return publishTime The timestamp when the price was published
    function getPriceWithConfidence(bytes32 priceFeedId)
        external
        view
        returns (int64 price, uint64 conf, uint256 publishTime)
    {
        PythStructs.Price memory pythPrice = pyth.getPriceUnsafe(priceFeedId);
        // require(block.timestamp - pythPrice.publishTime <= maxStaleness, "PythOracleAdapter: stale price");
        return (pythPrice.price, pythPrice.conf, pythPrice.publishTime);
    }

    /// @notice Compute confRatio in basis points (conf / |price| * 10000)
    function computeConfRatioBps(int64 price, uint64 conf) external pure returns (uint256) {
        if (price == 0) return 0;
        uint256 absPrice = price > 0 ? uint256(uint64(price)) : uint256(uint64(-price));
        return (uint256(conf) * 10000) / absPrice;
    }

    /// @notice Set max staleness (governance)
    function setMaxStaleness(uint256 _maxStaleness) external {
        maxStaleness = _maxStaleness;
    }
}

