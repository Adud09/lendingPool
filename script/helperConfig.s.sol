// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";

contract helperConfig is Script {
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;

    struct NetworkConfig {
        address token;
        address collateralToken;
        address priceFeed;
        uint256 ltv;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = sepoliaConfig();
        } else {
            activeNetworkConfig = anvilConfig();
        }
    }

    function sepoliaConfig() public returns (NetworkConfig memory) {
        return NetworkConfig({
            token: 0xd87764FCB9067BF36E2Da3ADad601C4aD86902e1,
            collateralToken: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            ltv: 50
        });
    }

    function anvilConfig() public returns (NetworkConfig memory) {
        vm.startBroadcast();
        MockV3Aggregator ethUsdPrice = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);

        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH");

        ERC20Mock tokenMock = new ERC20Mock("LPToken", "LPT");

        vm.stopBroadcast();

        return NetworkConfig({
            token: address(tokenMock), collateralToken: address(wethMock), priceFeed: address(ethUsdPrice), ltv: 50
        });
    }
}
