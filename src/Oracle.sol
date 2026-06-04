// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

library Oracle {
    error Oracle_latePriceUpdate();
    error Oracle_priceLessThanZero();

    uint256 constant TIMEOUT = 3 hours;
    uint256 constant PRECISION = 1e18;
    uint256 constant ADJUSTPRECISION = 1e10;

    function getPricePriceFeed(address priceFeed, uint256 amount) external view returns (uint256) {
        AggregatorV3Interface priceFeedInterface = AggregatorV3Interface(priceFeed);
        (, int256 price,, uint256 updatedAt,) = priceFeedInterface.latestRoundData();
        uint256 intervalSince = block.timestamp - updatedAt;
        
        if (intervalSince > TIMEOUT) {
            revert Oracle_latePriceUpdate();
        }

        if (price <= 0) {
            revert Oracle_priceLessThanZero();
        }
        return (uint256(price) * ADJUSTPRECISION * amount) / PRECISION;
    }
}
