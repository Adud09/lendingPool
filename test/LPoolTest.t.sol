// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {LendingPool} from "src/LendingPool.sol";
import {helperConfig} from "script/helperConfig.s.sol";
import {LPoolDeployScript} from "script/LPoolDeployScript.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract LPoolTest is Test {
    LendingPool LPool;
    helperConfig config;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address han = makeAddr("han");

    address token;
    address collateralToken;
    address priceFeed;
    uint256 ltv;

    uint256 constant INITIAL_LIQUIDITY_BALANCE = 5000000e18;
    uint256 constant INITIAL_COLATERAL_BALANCE = 200e18;
    uint256 constant UNSAFECOLLATERAL_WITHDRAW = 199e18;
    uint256 constant SAFEAMOUNTTOBORROW = 20000e18;
    uint256 constant LIQUIDITY_DEPOSIT = 2000000e18;
    uint256 constant FIRSTUSER_LIQUIDITY_DEPOSIT = 1000e18;
    uint256 constant BADBORROWAMOUNT = 210000e18;
    uint256 constant RANDOMAMOUNT_FORREVRTING_CHECK = 3000000000000e18;
    uint256 constant PATIALREPAYAMOUNT = 10000e18;
    uint256 constant FULLREPAYMENT = 20000e18;
    uint256 constant RATE = 1200;
    uint256 constant MAX_BP = 10000;
    uint256 constant SAFECOLLATERAL_WITHDRAW = 180e18;

    uint256 constant ZERO = 0;
    uint256 constant OTHERUSERS_DEPOSIT = 500e18;

    address[] depositors;

    function setUp() external {
        LPoolDeployScript deployer = new LPoolDeployScript();
        (LPool, config) = deployer.run();
        (token, collateralToken, priceFeed, ltv) = config.activeNetworkConfig();
        deal(token, alice, INITIAL_LIQUIDITY_BALANCE);
        deal(collateralToken, bob, INITIAL_COLATERAL_BALANCE);
        deal(token, bob, INITIAL_LIQUIDITY_BALANCE);
        deal(collateralToken, han, INITIAL_COLATERAL_BALANCE);
    }

    //////////////////////////////////////////
    ////     DEPOSIT LIQUIDITY TEST      ////
    /////////////////////////////////////////

    function testConstructorData() external {
        address tokenAddress = LPool.getLiquidityTokenAddress();
        address collateral = LPool.getCollateralTokenAddress();
        address priceFeeds = LPool.getPriceFeed();
        uint256 Ltv = LPool.getLTV();

        assert(token == tokenAddress);
        assert(collateralToken == collateral);
        assert(priceFeed == priceFeeds);
        assert(ltv == Ltv);
    }

    function testDepositLiquidityRevertIfTokenNotAllowed() external {
        ERC20Mock mytoken = new ERC20Mock("mytoken", "mtn");
        vm.expectRevert(LendingPool.lendingPool_tokenNotAllowed.selector);
        LPool.depositLiquidity(ZERO, address(mytoken));
    }

    function testDepossitLIquidityRevertBecauseOfZeroDeposit() external {
        vm.expectRevert(LendingPool.lendingPool_amountMustBeMoreThan.selector);
        LPool.depositLiquidity(ZERO, address(token));
    }

    function testDepossitLIquidityRevertBecauseOfSmallDeposit() external {
        vm.startPrank(alice);
        IERC20(token).approve(address(LPool), FIRSTUSER_LIQUIDITY_DEPOSIT);
        vm.expectRevert(LendingPool.lendingPool_amountLessThanMinDeposit.selector);
        LPool.depositLiquidity(99, address(token));
        vm.stopPrank();
    }

    function testDepositLiquiditySingleUserDeposit() external {
        uint256 protocolBalanceBefore = IERC20(token).balanceOf(address(LPool));
        console.log("protocol balance before", protocolBalanceBefore);

        uint256 totalProtocolLPSharesBefore = LPool.getTotalLiquidityShares();
        console.log("total protocol shares before", totalProtocolLPSharesBefore);
        uint256 totalUserLiquidityShareAfter = LPool.getUserLiquidityShares(alice);
        console.log("total user shares before", totalUserLiquidityShareAfter);

        vm.startPrank(alice);
        IERC20(token).approve(address(LPool), FIRSTUSER_LIQUIDITY_DEPOSIT);
        console.log("approved:", IERC20(token).allowance(alice, address(LPool)));
        LPool.depositLiquidity(FIRSTUSER_LIQUIDITY_DEPOSIT, address(token));
        vm.stopPrank();

        uint256 assumedProtocolTotalShare = FIRSTUSER_LIQUIDITY_DEPOSIT;
        uint256 assumedUserShare = FIRSTUSER_LIQUIDITY_DEPOSIT;

        console.log("new total protocol shares", LPool.getTotalLiquidityShares());
        console.log("new user shares", LPool.getUserLiquidityShares(alice));
        console.log("user balance after", IERC20(token).balanceOf(alice));
        console.log("protocol balance after", IERC20(token).balanceOf(address(LPool)));

        uint256 receivedProtocolBalanceAfter = IERC20(token).balanceOf(address(LPool)) - protocolBalanceBefore;

        uint256 protocolShareReceived = LPool.getTotalLiquidityShares() - totalProtocolLPSharesBefore;
        uint256 userShareReceived = LPool.getUserLiquidityShares(alice) - totalUserLiquidityShareAfter;

        assertEq(receivedProtocolBalanceAfter, FIRSTUSER_LIQUIDITY_DEPOSIT);
        assertEq(assumedProtocolTotalShare, protocolShareReceived);
        assertEq(assumedUserShare, userShareReceived);
    }

    function testmultipleUserDepositLiquidity() external {
        uint256 numberOfUsers = 3;
        uint160 i;
        address sender;

        for (i = 1; i <= numberOfUsers; i++) {
            sender = address(i);
            deal(token, sender, INITIAL_LIQUIDITY_BALANCE);

            vm.startPrank(sender);
            if (i == 1) {
                IERC20(token).approve(address(LPool), FIRSTUSER_LIQUIDITY_DEPOSIT);
                LPool.depositLiquidity(FIRSTUSER_LIQUIDITY_DEPOSIT, address(token));
            } else {
                IERC20(token).approve(address(LPool), OTHERUSERS_DEPOSIT);
                LPool.depositLiquidity(OTHERUSERS_DEPOSIT, address(token));
            }
            vm.stopPrank();
            depositors.push(sender);
        }

        uint256 totalProtocolAsset = LPool.getTotalPoolAsset();
        uint256 totalPoolShare = LPool.getTotalLiquidityShares();
        uint256 firstUser = LPool.getUserLiquidityShares(depositors[0]);
        uint256 secondUser = LPool.getUserLiquidityShares(depositors[1]);
        uint256 thirdUser = LPool.getUserLiquidityShares(depositors[2]);

        uint256 totalAssetToReceived = 2000e18;
        uint256 totalShareReceived = 2000e18;
        uint256 firstuserReceivedShare = 1000e18;
        uint256 secUserReceivedShare = 500e18;
        uint256 thirdUserReceivedShare = 500e18;

        assertEq(totalProtocolAsset, totalAssetToReceived);
        assertEq(totalPoolShare, totalShareReceived);
        assertEq(firstUser, firstuserReceivedShare);
        assertEq(secondUser, secUserReceivedShare);
        assertEq(thirdUser, thirdUserReceivedShare);
    }

    function testDepositLiquidityEmit() external {
        vm.startPrank(alice);
        IERC20(token).approve(address(LPool), FIRSTUSER_LIQUIDITY_DEPOSIT);
        console.log("approved:", IERC20(token).allowance(alice, address(LPool)));
        vm.expectEmit(true, false, false, true, address(LPool));
        emit LendingPool.liquidityDeposit(alice, FIRSTUSER_LIQUIDITY_DEPOSIT);
        LPool.depositLiquidity(FIRSTUSER_LIQUIDITY_DEPOSIT, address(token));
        vm.stopPrank();
    }

    ///////////////////////////////////////////////
    ////        DEPOSIT COLLATERAL            /////
    ///////////////////////////////////////////////

    function testDepositCollateralZeroDeposit() external {
        vm.expectRevert(LendingPool.lendingPool_amountMustBeMoreThan.selector);
        LPool.depositCollateral(ZERO, collateralToken);
    }

    function testDepositCollateralRevertInvalidAddress() external {
        vm.expectRevert(LendingPool.lendingPool_tokenNotAllowed.selector);
        LPool.depositCollateral(OTHERUSERS_DEPOSIT, token);
    }

    function testCollateralDeposit() external {
        uint256 collateralPoolBefore = LPool.getTotalCollateralPool();
        uint256 userCollateralBalanceBefore = LPool.getUserCollateralDeposit(bob);

        vm.startPrank(bob);
        IERC20(collateralToken).approve(address(LPool), INITIAL_COLATERAL_BALANCE);
        LPool.depositCollateral(INITIAL_COLATERAL_BALANCE, collateralToken);
        vm.stopPrank();

        uint256 collateralPoolAfter = LPool.getTotalCollateralPool();
        uint256 userCollateralAfter = LPool.getUserCollateralDeposit(bob);

        uint256 protocolReceivedAmount = collateralPoolAfter - collateralPoolBefore;
        uint256 userCollateralReceived = userCollateralAfter - userCollateralBalanceBefore;

        assertEq(protocolReceivedAmount, INITIAL_COLATERAL_BALANCE);
        assertEq(userCollateralReceived, INITIAL_COLATERAL_BALANCE);
    }

    function testDepositCollateralEmit() external {
        vm.startPrank(bob);
        IERC20(collateralToken).approve(address(LPool), INITIAL_COLATERAL_BALANCE);
        vm.expectEmit(true, false, false, true, address(LPool));
        emit LendingPool.liquidityDeposit(bob, INITIAL_COLATERAL_BALANCE);
        LPool.depositCollateral(INITIAL_COLATERAL_BALANCE, collateralToken);
        vm.stopPrank();
    }

    /////////////////////
    ////   BORROW   ////
    ////////////////////

    modifier depositLiquiditys() {
        vm.startPrank(alice);
        IERC20(token).approve(address(LPool), LIQUIDITY_DEPOSIT);
        console.log("approved:", IERC20(token).allowance(alice, address(LPool)));
        LPool.depositLiquidity(LIQUIDITY_DEPOSIT, address(token));
        vm.stopPrank();
        _;
    }

    modifier depositCollaterals() {
        vm.startPrank(bob);
        IERC20(collateralToken).approve(address(LPool), INITIAL_COLATERAL_BALANCE);
        LPool.depositCollateral(INITIAL_COLATERAL_BALANCE, collateralToken);
        vm.stopPrank();
        _;
    }

    function testZeroBorrowAmountRevert() external {
        vm.expectRevert(LendingPool.lendingPool_amountMustBeMoreThan.selector);
        LPool.borrow(ZERO);
    }

    function testBorrowAmountGreaterProtocolBalanceRevert() external depositLiquiditys depositCollaterals {
        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(LendingPool.lendingPool_amountMoreThanAvailableLiquidity.selector, LIQUIDITY_DEPOSIT)
        );
        LPool.borrow(RANDOMAMOUNT_FORREVRTING_CHECK);
        vm.stopPrank();
    }

    function testBorrorowRevertCauseOfWeakHealthFactor() external depositLiquiditys depositCollaterals {
        vm.startPrank(bob);
        vm.expectRevert(LendingPool.lendingPool_weakHealthFactor.selector);
        LPool.borrow(BADBORROWAMOUNT);
        vm.stopPrank();
    }

    function testBorrorow() external depositLiquiditys depositCollaterals {
        uint256 spendableAmountBalanceBefore = LPool.getTotalSpendableAmount();
        uint256 userBalanceBefore = IERC20(LPool.getLiquidityTokenAddress()).balanceOf(bob);

        vm.startPrank(bob);
        LPool.borrow(SAFEAMOUNTTOBORROW);
        vm.stopPrank();

        uint256 spendableAmountBalanceAfter = LPool.getTotalSpendableAmount();
        uint256 userBalanceAfter = IERC20(LPool.getLiquidityTokenAddress()).balanceOf(bob);

        uint256 amountLeavingProtocol = spendableAmountBalanceBefore - spendableAmountBalanceAfter;
        uint256 amountBeingReceivedByUser = userBalanceAfter - userBalanceBefore;

        assertEq(amountLeavingProtocol, SAFEAMOUNTTOBORROW);
        assertEq(amountBeingReceivedByUser, SAFEAMOUNTTOBORROW);
    }

    /////////////////////////////////
    /////        REPAY       ///////
    ////////////////////////////////

    function testZeroRepayAmountRevert() external {
        vm.expectRevert(LendingPool.lendingPool_amountMustBeMoreThan.selector);
        LPool.repay(ZERO);
    }

    modifier borrows() {
        vm.startPrank(bob);
        LPool.borrow(SAFEAMOUNTTOBORROW);
        vm.stopPrank();
        _;
    }

    function testZeroDebtShareRevert() external {
        vm.expectRevert(LendingPool.lendingPool_zeroDebtShares.selector);
        LPool.repay(RANDOMAMOUNT_FORREVRTING_CHECK);
    }

    function testAmountGreaterThanDebtRevert() external depositLiquiditys depositCollaterals borrows {
        vm.startPrank(bob);
        vm.expectRevert(LendingPool.lendingPool_amountMoreThanDebt.selector);
        LPool.repay(RANDOMAMOUNT_FORREVRTING_CHECK);
        vm.stopPrank();
    }

    function testRepayPatialDebt() external depositLiquiditys depositCollaterals borrows {
        uint256 debtShareBefore = LPool.getUserDebtShare(bob);
        uint256 totalDebtShareBefore = LPool.getTotalDebtShare();

        vm.startPrank(bob);
        IERC20(token).approve(address(LPool), PATIALREPAYAMOUNT);
        LPool.repay(PATIALREPAYAMOUNT);
        vm.stopPrank();

        uint256 debtShareAfter = LPool.getUserDebtShare(bob);
        uint256 totalDebtAfter = LPool.getTotalDebtShare();

        uint256 debtshareDedutAmount = debtShareBefore - debtShareAfter;
        uint256 totalUserDebtShareDedut = totalDebtShareBefore - totalDebtAfter;

        assertEq(debtshareDedutAmount, PATIALREPAYAMOUNT);
        assertEq(totalUserDebtShareDedut, PATIALREPAYAMOUNT); // the debt share being dedut will be the same amount being repaid since the debt havent grow yet
    }

    function testRepayFullDebt() external depositLiquiditys depositCollaterals borrows {
        uint256 debtShareBefore = LPool.getUserDebtShare(bob);
        uint256 totalDebtShareBefore = LPool.getTotalDebtShare();

        vm.startPrank(bob);
        IERC20(token).approve(address(LPool), FULLREPAYMENT);
        LPool.repay(FULLREPAYMENT);
        vm.stopPrank();

        uint256 debtShareAfter = LPool.getUserDebtShare(bob);
        uint256 totalDebtAfter = LPool.getTotalDebtShare();

        uint256 debtshareDedutAmount = debtShareBefore - debtShareAfter;
        uint256 totalUserDebtShareDedut = totalDebtShareBefore - totalDebtAfter;

        assertEq(debtshareDedutAmount, FULLREPAYMENT);
        assertEq(totalUserDebtShareDedut, FULLREPAYMENT); // the debt share being dedut will be the same amount being repaid since the debt havent grow yet
    }

    function testRepayFullDebtWithoutFee() external depositLiquiditys depositCollaterals borrows {
        uint256 interest = (LPool.getTotalDebt() * RATE * 180 days) / (MAX_BP * 365 days);

        vm.warp(block.timestamp + 180 days);

        vm.prank(bob);
        LPool.currentInterest();

        uint256 debtAfterInterest = LPool.getTotalDebt();
        console.log("fullDebtAfter:", debtAfterInterest);

        vm.startPrank(bob);
        IERC20(token).approve(address(LPool), FULLREPAYMENT);
        LPool.repay(FULLREPAYMENT);
        vm.stopPrank();

        assertEq(LPool.getTotalDebt(), interest);
        assertGt(debtAfterInterest, FULLREPAYMENT);
    }

    function testDebtInterestWithMultipleUser() external depositLiquiditys depositCollaterals borrows {
        vm.startPrank(han);
        IERC20(collateralToken).approve(address(LPool), INITIAL_COLATERAL_BALANCE);
        LPool.depositCollateral(INITIAL_COLATERAL_BALANCE, collateralToken);

        LPool.borrow(10000e18);
        vm.stopPrank();

        uint256 interest = (LPool.getShareToWorth(LPool.getUserDebtShare(bob)) * RATE * 180 days) / (MAX_BP * 365 days);

        vm.warp(block.timestamp + 180 days);

        vm.prank(bob);
        LPool.currentInterest();

        uint256 debtAfterInterest = LPool.getShareToWorth(LPool.getUserDebtShare(bob));
        console.log("fullDebtAfter:", debtAfterInterest);

        vm.startPrank(bob);
        IERC20(token).approve(address(LPool), FULLREPAYMENT);
        LPool.repay(FULLREPAYMENT);
        vm.stopPrank();

        uint256 fee = debtAfterInterest - FULLREPAYMENT;

        assertEq(fee, interest);
        assertGt(debtAfterInterest, FULLREPAYMENT);
    }

    //////////////////////////////////////////
    ////     WITHDRAW COLLATERAL         ////
    ////////////////////////////////////////

    function testrevertIfAMountToWithdrawIsZero() external {
        vm.expectRevert(LendingPool.lendingPool_amountMustBeMoreThan.selector);
        LPool.withdrawCollateral(ZERO);
    }

    function testRevertIfAmountIsGreaterThanCollateral() external {
        vm.expectRevert(LendingPool.lendingPool_invalidCollateralBalance.selector);
        LPool.withdrawCollateral(RANDOMAMOUNT_FORREVRTING_CHECK);
    }

    function testTryingWithdrawAmountThatWillTriggerWeakHealthFactor()
        external
        depositLiquiditys
        depositCollaterals
        borrows
    {
        vm.expectRevert(LendingPool.lendingPool_weakHealthFactor.selector);
        vm.startPrank(bob);
        LPool.withdrawCollateral(UNSAFECOLLATERAL_WITHDRAW);
        vm.stopPrank();
    }

    function testSafeCollateralWithdraw() external depositLiquiditys depositCollaterals borrows {
        vm.startPrank(bob);
        LPool.withdrawCollateral(SAFECOLLATERAL_WITHDRAW);
        vm.stopPrank();

        assertEq(LPool.getUserCollateralDeposit(bob), 20e18);
    }

    function testSafeCollateralWithdrawEmit() external depositLiquiditys depositCollaterals borrows {
        vm.startPrank(bob);
        vm.expectEmit(true, false, false, true, address(LPool));
        emit LendingPool.collateralWithdraw(bob, SAFECOLLATERAL_WITHDRAW);
        LPool.withdrawCollateral(SAFECOLLATERAL_WITHDRAW);
        vm.stopPrank();
    }

    /////////////////////////////
    /// WITHDRAWLIQUIDITY  /////
    ///////////////////////////

    modifier repay() {
        uint256 interest = (LPool.getTotalDebt() * RATE * 180 days) / (MAX_BP * 365 days);

        vm.warp(block.timestamp + 180 days);
        uint256 amountBeingRepaid = 21183561643835616438356;

        vm.prank(bob);
        LPool.currentInterest();

        console.log("totalAsset:", LPool.getTotalPoolAsset());
        console.log("totalinterst", interest);
        console.log("getshare", LPool.getDebtWorthToShare(LPool.getUserDebtShare(bob), amountBeingRepaid, bob));
        console.log("totaldebt", LPool.getShareToWorth(LPool.getUserDebtShare(bob)));

        console.log("totalRepay", FULLREPAYMENT + interest);

        vm.startPrank(bob);
        IERC20(token).approve(address(LPool), amountBeingRepaid); //  18882,565,959,648,215,209,519
        LPool.repay(amountBeingRepaid);
        vm.stopPrank();
        _;
    }

    function testrevertIfAMountToWithdrawLiquidityIsZero() external depositLiquiditys depositCollaterals borrows {
        vm.expectRevert(LendingPool.lendingPool_amountMustBeMoreThan.selector);
        LPool.withdrawLiquidity(ZERO);
    }

    function testrevertIfShareToWithdrawLiquidityIsZero() external depositLiquiditys depositCollaterals borrows {
        vm.expectRevert(LendingPool.lendingPool_zeroLiquidityShares.selector);
        vm.prank(bob); // note bob doesnt have any prior lp share
        LPool.withdrawLiquidity(RANDOMAMOUNT_FORREVRTING_CHECK);
    }

    function testrevertIfShareToWithdrawLiquidityIsMoreThanAvailableShare()
        external
        depositLiquiditys
        depositCollaterals
        borrows
    {
        vm.expectRevert(LendingPool.lendingPool_invalidLiquidityShare.selector);
        vm.prank(alice); // now alice is a valid LP
        LPool.withdrawLiquidity(RANDOMAMOUNT_FORREVRTING_CHECK);
    }

    function testRevertIfShareToWithDrawIsMoreThanWithDrawableBalance()
        external
        depositLiquiditys
        depositCollaterals
        borrows
    {
        console.log("spendableAmount:", LPool.getTotalSpendableAmount()); /// 1980000,000,000,000,000,000,000
        console.log("totalAsset:", LPool.getTotalPoolAsset()); /// 2000000,000,000,000,000,000,000

        vm.warp(block.timestamp + 180 days);
        LPool.currentInterest();

        console.log("totalAssetLater:", LPool.getTotalPoolAsset()); // totalPool Asset After Liquidity grows over time  2001183561643835616438356

        vm.expectRevert(LendingPool.lendingPoool_insufficientLiquidity.selector);

        uint256 shareAmount = 1980000000000000000000000;

        vm.prank(alice);
        LPool.withdrawLiquidity(shareAmount); // this aount is expected to fail even tho the shares amount is valid becuse the share amount is no longer
        // inquivalant to it self but higer value and the contract doesnt have up to that amount since debtor havent repay.

        console.log("totalAssetLater:", LPool.getTotalPoolAsset()); // 20000000000000000000000
    }

    function testSuccessPatialWithdraw() external depositLiquiditys depositCollaterals borrows {
        console.log("spendableAmount:", LPool.getTotalSpendableAmount()); /// 1980000,000,000,000,000,000,000
        console.log("totalAsset:", LPool.getTotalPoolAsset()); /// 2000000,000,000,000,000,000,000

        vm.warp(block.timestamp + 180 days);
        LPool.currentInterest();

        uint256 patialWithdrawShareAmount = 1900000000000000000000000;
        uint256 totalAssetBalanceBefore = LPool.getTotalPoolAsset();
        uint256 totalShareBalanceBefore = LPool.getTotalLiquidityShare(alice);
        uint256 userBalanceBefore = IERC20(token).balanceOf(alice);

        uint256 withdrawAmount = LPool.getLpShareToWorth(patialWithdrawShareAmount);

        console.log("totalAssetLater:", LPool.getTotalPoolAsset()); // totalPool Asset After Liquidity grows over time  2001183561643835616438356
        vm.prank(alice);
        LPool.withdrawLiquidity(patialWithdrawShareAmount); // this amount is suppose to pass because the share amount is inquivalent to valid wihdrawable amount

        uint256 totalAssetBalanceAfter = LPool.getTotalPoolAsset();
        uint256 totalShareBalanceAfter = LPool.getTotalLiquidityShare(alice);
        uint256 userBalanceAfter = IERC20(token).balanceOf(alice);

        uint256 amountSentFromProtocol = totalAssetBalanceBefore - totalAssetBalanceAfter;
        uint256 shareBurnt = totalShareBalanceBefore - totalShareBalanceAfter;
        uint256 amountReceivedByUser = userBalanceAfter - userBalanceBefore;

        assertEq(amountSentFromProtocol, withdrawAmount);
        assertEq(shareBurnt, patialWithdrawShareAmount);
        assertEq(amountReceivedByUser, withdrawAmount);
    }

    function testFullWithdrawLiqudityAfterRepayDebt() external depositLiquiditys depositCollaterals borrows repay {
        uint256 shareToWithdraw = 2000000e18;

        uint256 withdrawAmount = LPool.getLpShareToWorth(shareToWithdraw);

        uint256 userBalanceBefore = IERC20(token).balanceOf(alice);
        vm.prank(alice);
        LPool.withdrawLiquidity(shareToWithdraw); // this amount is suppose to pass because the share amount is inquivalent to valid wihdrawable amount
        uint256 userBalanceAfter = IERC20(token).balanceOf(alice);

        uint256 amountReceivedByUser = userBalanceAfter - userBalanceBefore;

        assertEq(amountReceivedByUser, withdrawAmount);
        assertEq(LPool.getTotalPoolAsset(), 0);
        assertEq(LPool.getTotalLiquidityShare(alice), 0);
    }

    function testWithdrawLiquidityEmit() external depositLiquiditys depositCollaterals borrows repay {
        uint256 shareToWithdraw = 2000000e18;
        uint256 withdrawAmount = LPool.getLpShareToWorth(shareToWithdraw);
        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(LPool));
        emit LendingPool.liquidityWithdraw(alice, withdrawAmount);
        LPool.withdrawLiquidity(shareToWithdraw); // this amount is suppose to pass because the share amount is inquivalent to valid wihdrawable amount
    }

    ///////////////////////////////////////
    //          LIQUIDATE TEST           //
    //////////////////////////////////////

    function testLiquidateRevertBecauseOfZeroDeposit() external {
        vm.expectRevert(LendingPool.lendingPool_amountMustBeMoreThan.selector);
        LPool.liquidate(ZERO, bob);
    }

    function testRevertWhenUserDebtIsSafe() external depositLiquiditys depositCollaterals borrows {
        vm.expectRevert(LendingPool.lendingPool_userHealthIsSafe.selector);
        LPool.liquidate(500, bob);
    }

    modifier newBorrow() {
        /// we will borrow larger amount to make sure bob health is close to being liquidate before we manipulate the price feed to make bob under collateralized and eligible for liquidation
        uint256 hugeAmountToBorrow = 200000e18;
        vm.startPrank(bob);
        LPool.borrow(hugeAmountToBorrow);
        console.log("bob health factor before price manipulation", LPool.getHealthFactor(bob));
        vm.stopPrank();

        /// now we will manipulate the price feed to make bob under collateralized and eligible for liquidation
        /// we will use the mock price feed to manipulate the price and make bob health factor under

        MockV3Aggregator priceFeedMock = MockV3Aggregator(priceFeed);
        priceFeedMock.updateAnswer(1900e8); /// this will make bob health factor under 1 and eligible for liquidation
        console.log("bob health factor After price manipulation", LPool.getHealthFactor(bob));

        _;
    }


    function testliquidateSuccessfulTransaction() external depositLiquiditys depositCollaterals newBorrow {
        uint256 amountToLiquidate = 5000e18;
        uint256 amountToShare = LPool.getDebtWorthToShare(LPool.getUserDebtShare(bob), amountToLiquidate, bob);
        uint256 userDebtShareBefore = LPool.getUserDebtShare(bob);
        uint256 userCollateralBefore = LPool.getUserCollateralDeposit(bob);
        uint256 liquidatorBalanceBefore = IERC20(collateralToken).balanceOf(alice);
        uint256 totalCollateralBefore = LPool.getTotalCollateralPool();

        vm.startPrank(alice);
        IERC20(token).approve(address(LPool), amountToLiquidate);
        LPool.liquidate(amountToLiquidate, bob);
        vm.stopPrank();

        uint256 userDebtShareAfter = LPool.getUserDebtShare(bob);
        uint256 userCollateralAfter = LPool.getUserCollateralDeposit(bob);
        uint256 liquidatorBalanceAfter = IERC20(collateralToken).balanceOf(alice);
        uint256 totalCollateralAfter = LPool.getTotalCollateralPool();

        uint256 bonus = (LPool.getAmountToCollateral(amountToLiquidate) * 10) / 100; // 10% bonus for liquidator
        uint256 assumedCollateralToReceive = LPool.getAmountToCollateral(amountToLiquidate) + bonus;


        assertEq(userCollateralBefore - userCollateralAfter,assumedCollateralToReceive);
        assertEq(liquidatorBalanceAfter - liquidatorBalanceBefore, assumedCollateralToReceive);
        assertEq(totalCollateralBefore - totalCollateralAfter,  assumedCollateralToReceive);
    }
}
