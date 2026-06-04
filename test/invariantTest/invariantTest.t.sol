// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {LendingPool} from "src/LendingPool.sol";
import {helperConfig} from "script/helperConfig.s.sol";
import {LPoolDeployScript} from "script/LPoolDeployScript.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Handler} from "./Handler.sol";


contract lendPoolOpenInvariantTest is StdInvariant, Test {

    LendingPool LPool;
    helperConfig config;
    Handler handler;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address han = makeAddr("han");

    uint256 constant INITIAL_LIQUIDITY_BALANCE = 5000000e18;
    uint256 constant INITIAL_COLATERAL_BALANCE = 200e18;

    address token;
    address collateralToken;
    address priceFeed;
    uint256 ltv;

    function setUp() external {
        LPoolDeployScript deployer = new LPoolDeployScript();
        (LPool, config) = deployer.run();
        (token, collateralToken, priceFeed, ltv) = config.activeNetworkConfig();
        deal(token, alice, INITIAL_LIQUIDITY_BALANCE);
        deal(collateralToken, bob, INITIAL_COLATERAL_BALANCE);
        deal(token, bob, INITIAL_LIQUIDITY_BALANCE);
        deal(collateralToken, han, INITIAL_COLATERAL_BALANCE);
        handler = new Handler(address(LPool), address(token), address(collateralToken));
        targetContract(address(handler));
    }  

    function invariant_totalPoolAssetShouldAlwaysBeEqualToTotalSpenableAmountPlusTotalDebt() external {
        uint256 totalPoolAsset = LPool.getTotalPoolAsset();
        uint256 totalSpendableLiquidity = LPool.getTotalSpendableAmount();
        uint256 totalDebt = LPool.getTotalDebt();
        uint256 totalSpendablePlusDebt = totalSpendableLiquidity + totalDebt;

        assertEq(totalSpendablePlusDebt,totalPoolAsset);

        console.log("depositGhostVariable:", handler.ghost_DepositLiquidity());
        console.log("boorwGhostVariable:", handler.ghost_borrow());
        console.log("DepositCollateralGhostVariable:", handler.ghost_DepositCollateral());
        console.log("repayGhostVariable:", handler.ghost_repay());
        console.log("WithdrawCollateralGhostVariable:", handler.ghost_withdrawCollateral());
        console.log("WithdrawLiquidityGhostVariable:", handler.ghost_withdrawLiquidity());
        console.log("liquidateGhostVariable:", handler.ghost_liquidate());
    }


    function invariant_LiquidityBalanceMatchesAccounting() external {
        uint256 totalSpendableLiquidity = LPool.getTotalSpendableAmount();
        uint256 protocolbalance = IERC20(token).balanceOf(address(LPool));

        assertEq(totalSpendableLiquidity,protocolbalance);
        console.log("depositGhostVariable:", handler.ghost_DepositLiquidity());
        console.log("borrowGhostVariable:", handler.ghost_borrow());
        console.log("DepositCollateralGhostVariable:", handler.ghost_DepositCollateral());
        console.log("repayGhostVariable:", handler.ghost_repay());
        console.log("WithdrawLiquidityGhostVariable:", handler.ghost_withdrawLiquidity());
        console.log("liquidateGhostVariable:", handler.ghost_liquidate());
    }

    function invariant_CollateralBalanceMatchesAccounting() external {
        uint256 totalAccountedCollateral = LPool.getTotalCollateralPool();
        uint256 protocolCollateralBalance = IERC20(collateralToken).balanceOf(address(LPool));     
        assertEq(totalAccountedCollateral,protocolCollateralBalance);
        console.log("depositGhostVariable:", handler.ghost_DepositLiquidity());
        console.log("borrowGhostVariable:", handler.ghost_borrow());
        console.log("DepositCollateralGhostVariable:", handler.ghost_DepositCollateral());
        console.log("repayGhostVariable:", handler.ghost_repay());
        console.log("WithdrawLiquidityGhostVariable:", handler.ghost_withdrawLiquidity());
        console.log("liquidateGhostVariable:", handler.ghost_liquidate());
    }



}