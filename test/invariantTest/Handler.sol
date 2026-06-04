// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LendingPool} from "src/LendingPool.sol";
import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    LendingPool LPool;

    constructor (address _LPool ,address _token, address _collateralAddress){
        LPool = LendingPool(_LPool);
        token = _token;
        collateralAddress = _collateralAddress;
    }

    uint256 public ghost_DepositLiquidity;
    uint256 public ghost_DepositCollateral;
    uint256 public ghost_borrow;
    uint256 public ghost_repay;
    uint256 public ghost_withdrawCollateral;
    uint256 public ghost_withdrawLiquidity;
    uint256 public ghost_liquidate;
    address token;
    address collateralAddress;
    address[] liquidityDepositors;
    address[] collateralProviders;
    address[] userInDebt;
    address[] userThatRepayDebt;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address john =  makeAddr("john");
    uint256 constant INITIAL_LIQUIDITY_BALANCE = 5000000e18;
    

    function depositLiquidity(uint256 amount, address tokenAddress) external {
        tokenAddress = token;
        amount = bound(amount, 100e18, 50000e18);
        vm.startPrank(alice);
        ERC20Mock(token).mint(alice,amount);
        IERC20(token).approve(address(LPool), amount);
        LPool.depositLiquidity(amount, address(tokenAddress));        
        vm.stopPrank();
        ghost_DepositLiquidity++;
        liquidityDepositors.push(alice);
    }

    function deposiCollateral(uint256 amount, address tokenAddress) external {
        tokenAddress = collateralAddress;
        amount =  bound(amount, 2e18, 7e18);
        vm.startPrank(bob);
        ERC20Mock(tokenAddress).mint(bob,amount);
        IERC20(tokenAddress).approve(address(LPool), amount);
        LPool.depositCollateral(amount,address(tokenAddress));
        vm.stopPrank();
        ghost_DepositCollateral++;
        collateralProviders.push(bob);
    }

    function borrow(uint256 amount) external {
        if (LPool.getTotalSpendableAmount() == 0) {
            return;
        }

        if (collateralProviders.length == 0) {
            return;
        }
        address user = collateralProviders[collateralProviders.length - 1];
        if (amount == 0) {
            return;
        }

        uint256 userCollateralToUsd = LPool.getPrice(LPool.getUserCollateralDeposit(user));
        uint256 maxDebtAllowed = userCollateralToUsd * 50 / 100;
        uint256 userShare = LPool.getUserDebtShare(user);
        uint256 adjustedAmount;
        if (userShare > 0) {

        uint256 previousDebt = LPool.getShareToWorth(userShare);
        if (previousDebt > maxDebtAllowed) {
            return;
        }
            adjustedAmount = maxDebtAllowed - previousDebt; 
        } else {
            adjustedAmount = maxDebtAllowed;
        }

        if (adjustedAmount == 0) {
            return;
        }

        amount = bound(amount, 1,adjustedAmount);

        if (amount > LPool.getTotalSpendableAmount()) {
            return;
        }

        

        vm.startPrank(user);
        LPool.borrow(amount);
        vm.stopPrank();

        ghost_borrow++;
        userInDebt.push(user);
    }

    function repay(uint256 amount) external {

        if (userInDebt.length == 0) {
            return;
        }     
        address user = userInDebt[userInDebt.length - 1];
        uint256 userDebtShare = LPool.getUserDebtShare(user);
        if (userDebtShare == 0) {
            return;
        }

        uint256 userDebt = LPool.getShareToWorth(userDebtShare);

        amount = bound(amount, 1, userDebt);
        deal(token, user, amount);

        vm.startPrank(user);
        IERC20(token).approve(address(LPool), amount);
        LPool.repay(amount);
        vm.stopPrank();
        userThatRepayDebt.push(user);
        ghost_repay++;

    }

    function withdrawCollateral(uint256 amount) external {
        if (userThatRepayDebt.length == 0) {
            return;
        }

        if (amount == 0) {
            return;
        }

        uint256 index;
        index = bound(index,0,(userThatRepayDebt.length - 1));
        address user = userThatRepayDebt[index]; // now we have a valid user 

        uint256 userBalance = LPool.getUserCollateralDeposit(user);
        if (userBalance == 0) {
            return;
        }
        amount = bound(amount, 1, userBalance);
        uint256 userDebtShare = LPool.getUserDebtShare(user);

        

        if (userDebtShare != 0) {
            uint256 userDebt = LPool.getShareToWorth(userDebtShare);// user debt balance
            uint256 userBalanceInUsd = LPool.getPrice(userBalance);
            uint256 amountAdjusted = userBalanceInUsd * 50 /100;
        
            uint256 amountUsd = LPool.getPrice(amount);
            
            if (amountUsd > amountAdjusted ) {
                return;
            }
            amountAdjusted -= amountUsd;
            uint256 health = (amountAdjusted * 1e18) /  userDebt;

            if (health < 1e18) {
                return;
            }
        }

        if (amount == 0) {
            return;
        }

        vm.startPrank(user);
        LPool.withdrawCollateral(amount);
        vm.stopPrank();
        ghost_withdrawCollateral++;

    }

    function withdrawLiquidity(uint256 amount) external {
        if (liquidityDepositors.length == 0) {
            return;
        }

        if (amount == 0) {
            return;
        }

        uint256 index;
        index = bound(index,0,(liquidityDepositors.length - 1));
        address user = liquidityDepositors[index]; // now we have a valid user 

        uint256 userShare = LPool.getUserLiquidityShares(user);
        if (userShare == 0) {
            return;
        }
        amount = bound(amount, 1, userShare);

        uint256 totatSependable = LPool.getTotalSpendableAmount();

        uint256 shareWorth = LPool.getLpShareToWorth(amount);

        if (shareWorth > totatSependable) {
            return;
        }

        vm.startPrank(user);
        LPool.withdrawLiquidity(amount);
        vm.stopPrank();

        ghost_withdrawLiquidity++;


    }

    function liquidate(uint256 amount, address debtor) external {


        if (userInDebt.length == 0) {
            return;
        }     

        uint256 index;
        index = bound(index,0,(userInDebt.length - 1));
        debtor = userInDebt[index];
        

        MockV3Aggregator priceFeedMock = MockV3Aggregator(LPool.getPriceFeed());
        priceFeedMock.updateAnswer(1000e8);



        uint256 userDebtShare = LPool.getUserDebtShare(debtor);

        if (userDebtShare == 0) {
            return;
        }

        uint256 userDebt = LPool.getShareToWorth(userDebtShare);

        amount = bound(amount, 1, userDebt);

        deal(token, john, amount);

        if (LPool.getHealthFactor(debtor) > 1e18) {
            return;
        }

        if (LPool.getUserCollateralDeposit(debtor) == 0) {
            return;
        } 

        vm.startPrank(john);
        IERC20(token).approve(address(LPool), amount);
        LPool.liquidate(amount, debtor);
        vm.stopPrank();

        ghost_liquidate++;
    }
}
