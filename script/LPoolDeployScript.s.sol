// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {LendingPool} from "src/LendingPool.sol";
import {helperConfig} from "./helperConfig.s.sol";

contract LPoolDeployScript is Script {
    address token;
    address collateralToken;
    address priceFeed;
    uint256 ltv;

    function run() external returns (LendingPool, helperConfig) {
        helperConfig config = new helperConfig();
        (token, collateralToken, priceFeed, ltv) = config.activeNetworkConfig();
        vm.startBroadcast();
        LendingPool LPool = new LendingPool(token, collateralToken, priceFeed, ltv);
        vm.stopBroadcast();
        return (LPool, config);
    }
}
