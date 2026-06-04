// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Oracle} from "./Oracle.sol";

/// @title LendingPool
/// @author Daniel Adu -BotForge
/// @notice This contract is a simple implementation of a lending pool where users can deposit liquidity, borrow against their collateral, and repay their debts. It also includes a liquidation mechanism for undercollateralized positions.
/// @dev The contract uses a share-based system for both liquidity providers and borrowers to track their contributions and debts. Interest is accrued over time, and the health factor is calculated to determine the safety of a borrower's position.

contract LendingPool is ReentrancyGuard {
    ///////////////////////////////////
    //           error              //
    //////////////////////////////////

    error lendingPool_tokenNotAllowed();
    error lendingPool_transferFailed();
    error lendingPool_amountMustBeMoreThan();
    error lendingPool_notAddressZero();
    error lendingPool_weakHealthFactor();
    error lendingPool_amountMoreThanAvailableLiquidity(uint256 amount);
    error lendingPool_zeroShareMinted();
    error lendingPool_zeroDebtShares();
    error lendingPool_zeroLiquidityShares();
    error lendingPool_amountMoreThanDebt();
    error lendingPool_zeroDebt();
    error lendingPool_invalidLiquidityShare();
    error lendingPool_zeroLiquidity();
    error lendingPoool_insufficientLiquidity();
    error lendingPool_invalidCollateralAmount();
    error lendingPool_invalidCollateralBalance();
    error lendingPool_userHealthIsSafe();
    error lendingPool_amountLessThanMinDeposit();

    //////////////////////////////////////
    /////        event               /////
    //////////////////////////////////////
    event liquidityDeposit(address indexed user, uint256 amount);
    event collateralFDeposit(address indexed user, uint256 amount);
    event borrowed(address indexed user, uint256 amount);
    event repaid(address indexed user, uint256 amount);
    event collateralWithdraw(address indexed user, uint256 amount);
    event liquidityWithdraw(address indexed user, uint256 amount);
    event liquidates(address indexed liquidator, address indexed user, uint256 amount);

    ///////////////////////////////////
    //         variables              //
    ///////////////////////////////////

    uint256 private totalLiquidityShares;
    uint256 private totalPoolAsset;
    uint256 private totalCollateralPool;
    uint256 private immutable i_LTV;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN = 1e18;
    uint256 private constant RATE = 1200;
    uint256 private constant MAX_BPS = 10000;
    uint256 private constant BONUS_RATIO = 10;
    uint256 private constant HUNDRED = 100;
    uint256 private constant MIN_DEPOSIT = 100e18;
    address private immutable i_liquidityToken;
    address private collateralTokenAddress;
    address private immutable i_priceFeed;
    uint256 private totalDebt;
    uint256 private totalDebtShare;
    uint256 private totalSpendableAmount;
    uint256 private lastAccuredTime;

    mapping(address user => uint256 shares) private userLiquidityShares;
    mapping(address borrower => uint256 collateralDeposit) private borrowerCollateralDeposit;
    mapping(address borrower => uint256 totalDebt) private userDebtshare;

    constructor(address _token, address _collateralToken, address _pricefeed, uint256 ltv) {
        i_liquidityToken = _token;
        collateralTokenAddress = _collateralToken;
        i_priceFeed = _pricefeed;
        i_LTV = ltv;
        lastAccuredTime = block.timestamp;
    }

    modifier amountCantBeZero(uint256 amount) {
        if (amount == 0) {
            revert lendingPool_amountMustBeMoreThan();
        }
        _;
    }

    modifier tokenAllowed(address token) {
        if (token != i_liquidityToken) {
            revert lendingPool_tokenNotAllowed();
        }
        _;
    }

    modifier isTokenAllowed(address token) {
        if (token != collateralTokenAddress) {
            revert lendingPool_tokenNotAllowed();
        }
        _;
    }

    ////////////////////////////////////////////////
    /////         main functions               ////
    ////////////////////////////////////////////////

    /// @notice Deposit liquidity into the pool and receive liquidity shares in return. The amount of shares received is proportional to the amount of liquidity deposited relative to the total pool asset. If it's the first deposit, the shares received will be equal to the amount deposited.
    /// @dev The function checks for non-reentrancy, validates the token, and ensures the amount is greater than zero. It then transfers the tokens from the user to the contract, calculates the liquidity shares to mint, updates the total pool asset and spendable amount, and emits a liquidityDeposit event.
    /// @param liquidityAmount The amount of liquidity to deposit.
    /// @param token The address of the token being deposited as liquidity.

    function depositLiquidity(uint256 liquidityAmount, address token)
        external
        nonReentrant
        tokenAllowed(token)
        amountCantBeZero(liquidityAmount)
    {
        liquidityAmount = tokenTransfer(liquidityAmount, token, msg.sender, address(this));

        if (liquidityAmount < MIN_DEPOSIT) {
            revert lendingPool_amountLessThanMinDeposit();
        }

        uint256 liquidityShares;
        if (totalLiquidityShares == 0) {
            totalLiquidityShares += liquidityAmount;
            userLiquidityShares[msg.sender] += liquidityAmount;
            liquidityShares += liquidityAmount;
        } else {
            liquidityShares = (liquidityAmount * totalLiquidityShares) / totalPoolAsset;
            totalLiquidityShares += liquidityShares;
            userLiquidityShares[msg.sender] += liquidityShares;
        }

        totalPoolAsset += liquidityAmount;
        totalSpendableAmount += liquidityAmount;

        if (liquidityShares == 0) {
            revert lendingPool_zeroShareMinted();
        }

        emit liquidityDeposit(msg.sender, liquidityAmount);
    }

    /// @notice Deposit collateral into the pool. The collateral will be used to secure any borrowings made by the user. The function checks for non-reentrancy, validates the token, and ensures the amount is greater than zero. It then transfers the collateral tokens from the user to the contract, updates the total collateral pool and the user's collateral deposit, and emits a liquidityDeposit event.
    /// @dev The function does not mint any shares for collateral deposits, as they are not part of the liquidity pool but are instead used to secure loans. The health factor of the user is not checked during collateral deposit, allowing users to add more collateral even if their current position is undercollateralized.
    /// @param collateralamount The amount of collateral to deposit.
    /// @param token The address of the token being deposited as collateral.

    function depositCollateral(uint256 collateralamount, address token)
        external
        nonReentrant
        isTokenAllowed(token)
        amountCantBeZero(collateralamount)
    {
        collateralamount = tokenTransfer(collateralamount, token, msg.sender, address(this));
        totalCollateralPool += collateralamount;
        borrowerCollateralDeposit[msg.sender] += collateralamount;
        emit liquidityDeposit(msg.sender, collateralamount);
    }

    function borrow(uint256 amount) external nonReentrant amountCantBeZero(amount) {
        accureInterest();

        if (amount > totalSpendableAmount) {
            revert lendingPool_amountMoreThanAvailableLiquidity(totalSpendableAmount);
        }

        uint256 userDebtS;
        if (totalDebtShare == 0) {
            totalDebtShare += amount;
            userDebtshare[msg.sender] += amount;
            userDebtS += amount;
        } else {
            userDebtS = (amount * totalDebtShare) / totalDebt;
            totalDebtShare += userDebtS;
            userDebtshare[msg.sender] += userDebtS;
        }

        if (userDebtS == 0) {
            revert lendingPool_zeroShareMinted();
        }

        if (amount > totalSpendableAmount) {
            revert lendingPool_amountMoreThanAvailableLiquidity(totalSpendableAmount);
        }

        totalSpendableAmount -= amount;
        totalDebt += amount;

        revertIfHealthFactorWeak(msg.sender);

        bool success = IERC20(i_liquidityToken).transfer(msg.sender, amount);
        if (!success) {
            revert lendingPool_transferFailed();
        }
        emit borrowed(msg.sender, amount);
    }

    /// @notice Repay a borrowed amount to the pool. The function checks for non-reentrancy and ensures the amount is greater than zero. It then transfers the repayment amount from the user to the contract, calculates the debt shares to burn based on the repayment amount, updates the total debt and total spendable amount, and emits a repaid event.
    /// @dev The function allows users to repay their debts partially or in full. The health factor of the user is checked after the repayment to ensure that the user's position is still safe. If the repayment amount exceeds the user's total debt, the function will revert with an error. The interest is accrued before the repayment to ensure that the user is repaying the most up-to-date amount of debt.
    /// @param amount The amount of debt to repay.

    function repay(uint256 amount) external nonReentrant amountCantBeZero(amount) {
        accureInterest();
        _repay(amount, msg.sender, msg.sender);
        emit repaid(msg.sender, amount);
    }

    /// @notice Withdraw liquidity from the pool by burning liquidity shares. The function checks for non-reentrancy and ensures the share amount is greater than zero. It then calculates the amount of liquidity to withdraw based on the shares, updates the total liquidity shares, total pool asset, and total spendable amount, and emits a liquidityWithdraw event.
    /// @dev The function allows liquidity providers to withdraw their liquidity partially or in full by burning their liquidity shares. The health factor of the user is checked after the withdrawal to ensure that the user's position is still safe. If the share amount exceeds the user's liquidity shares, the function will revert with an error. The interest is accrued before the withdrawal to ensure that the health factor is calculated based on the most up-to-date information. If the amount to withdraw exceeds the total spendable amount in the pool, the function will revert with an error indicating insufficient liquidity.
    /// @param share The amount of liquidity shares to burn in order to withdraw liquidity from the pool. The amount of liquidity withdrawn will be proportional to the shares burned relative to the total liquidity shares in the pool.

    function withdrawLiquidity(uint256 share) external nonReentrant amountCantBeZero(share) {
        accureInterest();

        if (totalLiquidityShares == 0 || userLiquidityShares[msg.sender] == 0) {
            revert lendingPool_zeroLiquidityShares();
        }

        if (share > userLiquidityShares[msg.sender]) {
            revert lendingPool_invalidLiquidityShare();
        }

        uint256 amountToWithdraw = ShareToWorth(share);

        if (amountToWithdraw == 0) {
            revert lendingPool_zeroShareMinted();
        }

        if (amountToWithdraw > totalSpendableAmount) {
            revert lendingPoool_insufficientLiquidity();
        }

        totalLiquidityShares -= share;
        userLiquidityShares[msg.sender] -= share;
        totalSpendableAmount -= amountToWithdraw;
        totalPoolAsset -= amountToWithdraw;

        bool success = IERC20(i_liquidityToken).transfer(msg.sender, amountToWithdraw);
        if (!success) {
            revert lendingPool_transferFailed();
        }

        emit liquidityWithdraw(msg.sender, amountToWithdraw);
    }

    /// @notice Withdraw collateral from the pool. The function checks for non-reentrancy and ensures the amount is greater than zero. It then updates the total collateral pool and the user's collateral deposit, checks the health factor of the user to ensure that the position is still safe after the withdrawal, and emits a collateralWithdraw event.
    /// @dev The function allows users to withdraw their collateral partially or in full. The health factor of the user is checked after the withdrawal to ensure that the user's position is still safe. If the withdrawal amount exceeds the user's collateral deposit, the function will revert with an error. The interest is accrued before the withdrawal to ensure that the health factor is calculated based on the most up-to-date information.
    /// @param amount The amount of collateral to withdraw.

    function withdrawCollateral(uint256 amount) external nonReentrant amountCantBeZero(amount) {
        accureInterest();
        _withdrawCollateral(amount, msg.sender, msg.sender);
        emit collateralWithdraw(msg.sender, amount);
    }

    /// @notice Liquidate an undercollateralized position. The function checks for non-reentrancy and ensures the amount is greater than zero. It then checks the health factor of the debtor, and if it is below the minimum threshold, it allows the liquidator to repay a portion of the debtor's debt and receive a corresponding amount of collateral as a reward. The function updates the total debt, total spendable amount, and total collateral pool accordingly, and emits a liquidates event.
    /// @dev The function allows anyone to liquidate an undercollateralized position by repaying a portion of the debtor's debt. The liquidator receives a bonus in the form of additional collateral for taking on the risk of liquidating the position. The health factor of the debtor is checked before allowing liquidation to ensure that only undercollateralized positions can be liquidated. The interest is accrued before the liquidation to ensure that the health factor is calculated based on the most up-to-date information. If the liquidation amount exceeds the debtor's total debt, the function will revert with an error.
    /// @param amount The amount of debt to repay on behalf of the debtor.
    /// @param debtor The address of the debtor whose position is being liquidated.

    function liquidate(uint256 amount, address debtor) external nonReentrant amountCantBeZero(amount) {
        accureInterest();

        if (healthFactor(debtor) > MIN) {
            revert lendingPool_userHealthIsSafe();
        }
        _repay(amount, debtor, msg.sender);
        uint256 collateralAmount = amountToCollateral(amount);
        uint256 bonus = (collateralAmount * BONUS_RATIO) / HUNDRED;
        uint256 amountToSend = collateralAmount + bonus;

        if (amountToSend > borrowerCollateralDeposit[debtor]) {
            amountToSend = borrowerCollateralDeposit[debtor];
        }

        _withdrawCollateralLiquidate(amountToSend, debtor, msg.sender);
        emit liquidates(msg.sender, debtor, amount);
    }

    /////////////////////////////////////////
    ////     Private view functions      ///
    ///////////////////////////////////////

    // @notice A private function to handle token transfers from a sender to a receiver. It checks the balance of the receiver before and after the transfer to calculate the actual amount received, which is important for tokens that may have transfer fees. The function reverts if the transfer fails.
    /// @dev This function is used to ensure that the contract correctly accounts for the amount of tokens received, especially for tokens that have transfer fees or other mechanisms that may reduce the amount received compared to the amount sent. By checking the balance before and after the transfer, the function can accurately determine the amount that was actually received by the contract, which is crucial for maintaining accurate accounting in the lending pool. The function also ensures that the transfer was successful and reverts if it was not.
    /// @param amount The amount of tokens to transfer from the sender to the receiver.
    /// @param token The address of the token being transferred.
    /// @param sender The address of the sender from whom the tokens are being transferred.
    /// @param receiver The address of the receiver to whom the tokens are being transferred.

    function tokenTransfer(uint256 amount, address token, address sender, address receiver) private returns (uint256) {
        uint256 balanceBefore = IERC20(token).balanceOf(receiver);
        bool success = IERC20(token).transferFrom(sender, receiver, amount);
        if (!success) {
            revert lendingPool_transferFailed();
        }
        uint256 balanceAfter = IERC20(token).balanceOf(receiver);
        uint256 amountReceived = balanceAfter - balanceBefore;
        return amountReceived;
    }

    // @notice A private function to convert a given amount of debt shares into its equivalent worth in the underlying asset. The function checks if the total debt shares are zero to prevent division by zero errors and reverts if that is the case. The worth is calculated based on the proportion of the given shares to the total debt shares, multiplied by the total debt.
    /// @dev This function is used to determine the actual amount of debt that corresponds to a given number of debt shares. It is essential for accurately calculating the user's debt and for determining how much a user needs to repay when they want to reduce their debt shares. The function ensures that the total debt shares are not zero before performing the calculation to avoid division by zero errors, which could lead to incorrect calculations and potential vulnerabilities in the contract. By converting debt shares to their worth in the underlying asset, the contract can maintain accurate accounting of users' debts and ensure that repayments and liquidations are handled correctly.
    /// @param share The amount of debt shares to convert to worth.

    function debtShareToWorth(uint256 share) private view amountCantBeZero(share) returns (uint256) {
        if (totalDebtShare == 0) {
            revert lendingPool_zeroDebtShares();
        }

        uint256 worth = (share * totalDebt) / totalDebtShare;
        return worth;
    }

    // @notice A private function to convert a given amount of debt in the underlying asset into its equivalent number of debt shares. The function checks if the total debt is zero to prevent division by zero errors and reverts if that is the case. The shares are calculated based on the proportion of the given amount to the total debt, multiplied by the total debt shares.
    /// @dev This function is used to determine how many debt shares correspond to a given amount of debt in the underlying asset. It is essential for accurately calculating how many shares a user needs to acquire when they borrow a certain amount or how many shares they need to burn when they repay a certain amount. The function ensures that the total debt is not zero before performing the calculation to avoid division by zero errors, which could lead to incorrect calculations and potential vulnerabilities in the contract. By converting amounts of debt to their corresponding shares, the contract can maintain accurate accounting of users' debts and ensure that borrowing and repayment actions are handled correctly.
    /// @param amount The amount of debt in the underlying asset to convert to debt shares.

    function worthToDebtShare(uint256 amount, uint256 borrowerDebt, address user)
        private
        view
        amountCantBeZero(amount)
        returns (uint256)
    {
        if (totalDebt == 0) {
            revert lendingPool_zeroDebt();
        }

        uint256 share = (amount * userDebtshare[user]) / borrowerDebt;
        return share;
    }

    // @notice A private function to convert a given amount of liquidity shares into its equivalent worth in the underlying asset. The function checks if the total liquidity shares or total pool asset are zero to prevent division by zero errors and reverts if that is the case. The worth is calculated based on the proportion of the given shares to the total liquidity shares, multiplied by the total pool asset.
    /// @dev This function is used to determine the actual amount of underlying asset that corresponds to a given number of liquidity shares. It is essential for accurately calculating how much a liquidity provider can withdraw when they burn their liquidity shares. The function ensures that the total liquidity shares and total pool asset are not zero before performing the calculation to avoid division by zero errors, which could lead to incorrect calculations and potential vulnerabilities in the contract. By converting liquidity shares to their worth in the underlying asset, the contract can maintain accurate accounting of liquidity providers' shares and ensure that withdrawals are handled correctly. This function is crucial for maintaining the integrity of the liquidity pool and ensuring that liquidity providers receive the correct amount of underlying  asset when they withdraw their liquidity.
    /// @param share The amount of liquidity shares to convert to worth.

    function ShareToWorth(uint256 share) private view amountCantBeZero(share) returns (uint256) {
        if (totalLiquidityShares == 0 || totalPoolAsset == 0) {
            revert lendingPool_zeroDebtShares();
        }

        uint256 worth = (share * totalPoolAsset) / totalLiquidityShares;
        return worth;
    }

    // @notice A private function to convert a given amount of the underlying asset into its equivalent number of liquidity shares. The function checks if the total liquidity shares or total pool asset are zero to prevent division by zero errors and reverts if that is the case. The shares are calculated based on the proportion of the given amount to the total pool asset, multiplied by the total liquidity shares.
    /// @dev This function is used to determine how many liquidity shares correspond to a given amount of the underlying asset. It is essential for accurately calculating how many shares a liquidity provider needs to acquire when they deposit a certain amount or how many shares they need to burn when they withdraw a certain amount. The function ensures that the total liquidity shares and total pool asset are not zero before performing the calculation to avoid division by zero errors, which could lead to incorrect calculations and potential vulnerabilities in the contract. By converting amounts of the underlying asset to their corresponding shares, the contract can maintain accurate accounting of liquidity providers' shares and ensure that deposits and withdrawals are handled correctly. This function is crucial for maintaining the   integrity of the liquidity pool and ensuring that liquidity providers receive the correct amount of shares when they deposit or withdraw their liquidity.
    /// @param amount The amount of the underlying asset to convert to liquidity shares.

    function worthToShare(uint256 amount) private view amountCantBeZero(amount) returns (uint256) {
        if (totalLiquidityShares == 0 || totalPoolAsset == 0) {
            revert lendingPool_zeroLiquidity();
        }

        uint256 share = (amount * totalLiquidityShares) / totalPoolAsset;
        return share;
    }

    // @notice A private function to get the price of a given amount of the underlying asset in USD using an oracle. The function checks if the amount is greater than zero and reverts if it is not. It then calls the oracle to get the price based on the provided price feed address and the amount.
    /// @dev This function is used to determine the value of the collateral in USD, which is essential for calculating the health factor of a borrower's position and for determining whether a position is undercollateralized and subject to liquidation. The function ensures that the amount is greater than zero before calling the oracle to avoid unnecessary calls and potential errors. By using an oracle to get the price, the contract can maintain accurate and up-to-date information about the value of the collateral, which is crucial for maintaining the integrity of the lending pool and ensuring that borrowers' positions are evaluated correctly based on the current
    /// market conditions. This function is a key component of the risk management system of the lending pool, as it allows the contract to assess the value of collateral and make informed decisions about borrowing, repayment, and liquidation.
    /// @param amount The amount of the underlying asset for which to get the price in USD.

    function getPrice(uint256 amount) public view  returns (uint256) {
        return Oracle.getPricePriceFeed(i_priceFeed, amount);
    }

    // @notice A private function to get the total debt and collateral value in USD for a given user. The function retrieves the user's collateral deposit and converts it to USD using the getPrice function. It also retrieves the user's debt shares and converts them to their equivalent worth in the underlying asset, which is then converted to USD. The function returns the total debt and collateral value in USD.
    /// @dev This function is used to gather the necessary information about a user's position in the lending pool, specifically the total debt and the value of the collateral in USD. This information is crucial for calculating the health factor of the user's position and for making informed decisions about borrowing, repayment, and liquidation. The function ensures that the amount of collateral and debt shares are properly converted to their USD values
    /// using the getPrice function and the debtShareToWorth function, respectively. By providing a clear view of the user's financial position in the lending pool, this function helps maintain the integrity of the system and ensures that users are aware of their obligations and risks when interacting with the lending pool. The information returned by this function is essential for both users and the contract to manage risk effectively and make informed decisions about their interactions with the lending pool.
    /// @param user The address of the user for whom to get the information.

    function getUserInformation(address user) private view returns (uint256, uint256) {
        uint256 collateralInUsd = getPrice(borrowerCollateralDeposit[user]);
        uint256 totalUseDebtShare = userDebtshare[user];

        if (totalUseDebtShare == 0 || totalDebtShare == 0) {
            return (0, collateralInUsd);
        }

        uint256 totaldebt = (totalUseDebtShare * totalDebt) / totalDebtShare;

        return (totaldebt, collateralInUsd);
    }

    // @notice A private function to calculate the health factor of a user's position in the lending pool. The health factor is calculated as the adjusted collateral value in USD divided by the total debt in USD. The adjusted collateral value is the collateral value multiplied by the LTV ratio. If the total debt is zero, the function returns the maximum possible health factor to indicate that the position is safe.
    /// @dev This function is used to assess the safety of a user's position in the lending pool by calculating the health factor, which is a key metric for determining whether a position is undercollateralized and subject to liquidation. The function retrieves the total debt and collateral value in USD using the
    ///getUserInformation function, and then calculates the adjusted collateral value based on the LTV ratio. The health factor is calculated as the adjusted collateral value divided by the total debt. If the total debt is zero, the function returns the maximum possible health factor to indicate that the position is safe and not at risk of liquidation. This function is crucial for maintaining the integrity of the lending pool and ensuring that users are aware of their financial position and risks when interacting with the lending pool. By providing a clear assessment of the health of a user's position, this function helps users make informed decisions about borrowing, repayment, and collateral management, and it also allows the contract to manage risk effectively by identifying undercollateralized positions that may need to be liquidated.
    /// @param user The address of the user for whom to calculate the health factor.

    function healthFactor(address user) private view returns (uint256) {
        (uint256 totalDebts, uint256 collateralInUsd) = getUserInformation(user);
        if (totalDebts == 0) {
            return type(uint96).max;
        }
        uint256 adjustedCollateral = (collateralInUsd * i_LTV) / 100;
        uint256 health = (adjustedCollateral * PRECISION) / totalDebts;
        return health;
    }

    // @notice A private function to convert a given repayment amount in the underlying asset into its equivalent amount of collateral based on the current price. The function checks if the repayment amount is greater than zero and reverts if it is not. It then retrieves the price of the collateral in USD using the getPrice function and calculates the equivalent amount of collateral based on the repayment amount and the collateral price.
    /// @dev This function is used during the liquidation process to determine how much collateral a liquidator should receive in exchange for repaying a certain amount of the debtor's debt. By converting the repayment amount into its equivalent collateral value, the contract can ensure that the liquidator receives a fair amount of collateral based on the current market price. The function ensures that the repayment amount is greater than zero
    /// before performing the calculation to avoid unnecessary calls and potential errors. By using the getPrice function to retrieve the current price of the collateral, the contract can maintain accurate and up-to-date information for the liquidation process, which is crucial for maintaining the integrity of the lending pool and ensuring that liquidations are handled correctly based on current market conditions. This function is a key component of the liquidation mechanism of the lending pool, as it allows the contract to determine the appropriate amount of collateral to transfer to the liquidator in exchange for repaying a portion of the debtor's debt.
    /// @param repayAmount The amount of debt being repaid by the liquidator, which will be converted into an equivalent amount of collateral to be transferred to the liquidator as part of the liquidation process.

    function amountToCollateral(uint256 repayAmount) private view amountCantBeZero(repayAmount) returns (uint256) {
        uint256 collateralPrice = getPrice(PRECISION);
        uint256 collateralAmount = (repayAmount * PRECISION) / collateralPrice;
        return collateralAmount;
    }

    /////////////////////////////////////////////////
    /////         helper functions               ////
    /////////////////////////////////////////////////

    // @notice A private function to handle the withdrawal of collateral from a user's position. The function checks if the withdrawal amount is greater than zero and reverts if it is not. It then checks if the user has enough collateral deposited to cover the withdrawal amount, updates the user's collateral deposit and the total collateral pool, checks the health factor of the user to ensure that the position is still safe after the withdrawal, and transfers the withdrawn collateral to the specified address. If the transfer fails, the function reverts with an error.
    /// @dev This function is used to manage the withdrawal of collateral from a user's position in the lending pool. It ensures that users cannot withdraw more collateral than they have deposited, and it also checks the health factor after the withdrawal to ensure that the user's position remains safe and not undercollateralized. The function is designed to be used both for regular collateral withdrawals by the user and for collateral transfers during the liquidation process. By centralizing the logic for collateral withdrawal in this function, the contract
    /// can maintain consistent checks and updates related to collateral management, which helps maintain the integrity of the lending pool and ensures that users' positions are managed correctly. The function also handles the actual transfer of collateral tokens to the user or liquidator, ensuring that the correct amount of collateral is transferred based on the withdrawal request. This function is crucial for maintaining the proper functioning of the lending pool and ensuring that collateral management is handled securely and efficiently.
    /// @param amount The amount of collateral to withdraw from the user's position.
    /// @param from The address of the user from whom the collateral is being withdrawn.
    /// @param to The address to which the withdrawn collateral will be transferred.

    function _withdrawCollateral(uint256 amount, address from, address to) private amountCantBeZero(amount) {
        if (amount > borrowerCollateralDeposit[from]) {
            revert lendingPool_invalidCollateralBalance();
        }

        borrowerCollateralDeposit[from] -= amount;
        totalCollateralPool -= amount;

        revertIfHealthFactorWeak(from);

        bool success = IERC20(collateralTokenAddress).transfer(to, amount);
        if (!success) {
            revert lendingPool_transferFailed();
        }
    }

    /// @notice A private function to handle the withdrawal of collateral during the liquidation process. The function checks if the withdrawal amount is greater than zero and reverts if it is not. It then checks if the user has enough collateral deposited to cover the withdrawal amount, updates the user's collateral deposit and the total collateral pool, and transfers the withdrawn collateral to the specified address. If the transfer fails, the function reverts with an error. This function does not check the health factor of the user after the withdrawal, as it is intended to be used during liquidation when the user's position is already undercollateralized.
    /// @dev This function is specifically designed for the liquidation process, where a liquidator is withdrawing collateral from a debtor's position in exchange for repaying a portion of the debtor's debt. Since the user's position is already undercollateralized at this point, there is no need to check
    /// the health factor after the withdrawal, as the position is already at risk of liquidation. By separating this logic from the regular collateral withdrawal function, the contract can ensure that the appropriate checks and updates are made based on the context of the withdrawal, which helps maintain the integrity of the lending pool and ensures that liquidations are handled correctly. This function is crucial for managing the collateral during the liquidation process and ensuring that liquidators receive the correct amount of collateral based on their repayment of the debtor's debt.
    /// @param amount The amount of collateral to withdraw from the user's position during liquidation.
    /// @param from The address of the user from whom the collateral is being withdrawn during liquidation.
    /// @param to The address to which the withdrawn collateral will be transferred during liquidation.

    function _withdrawCollateralLiquidate(uint256 amount, address from, address to) private {
        if (amount > borrowerCollateralDeposit[from]) {
            revert lendingPool_invalidCollateralBalance();
        }

        borrowerCollateralDeposit[from] -= amount;
        totalCollateralPool -= amount;

        bool success = IERC20(collateralTokenAddress).transfer(to, amount);
        if (!success) {
            revert lendingPool_transferFailed();
        }
    }

    /// @notice A private function to handle the repayment of debt by a user or a liquidator. The function checks if the repayment amount is greater than zero and reverts if it is not. It then checks if the user has any debt shares and if the repayment amount exceeds the user's total debt, reverting with an error if either condition is true. The function transfers the repayment amount from the payer to the contract, calculates the corresponding debt shares to burn based on the repayment amount, updates the total debt, total spendable amount, and total debt shares, and updates the user's debt shares accordingly. This function is used for both regular repayments by users and repayments made by liquidators during the liquidation process.
    /// @dev This function is designed to handle the logic for repaying debt in the lending pool. It ensures that users cannot repay more than their total debt and that they have debt shares to burn when making a repayment. The function also updates the total debt and total spendable amount in the
    /// pool based on the repayment, and it calculates the corresponding debt shares to burn to maintain accurate accounting of users' debts. By centralizing the repayment logic in this function, the contract can maintain consistent checks and updates related to debt management, which helps maintain the integrity of the lending pool and ensures that repayments are handled correctly for both users and liquidators. This function is crucial for managing the repayment process and ensuring that users' debts are updated accurately when they make repayments or when liquidators repay on behalf of undercollateralized positions during liquidation.
    /// @param repayAmount The amount of debt being repaid by the user or liquidator, which will be used to calculate the corresponding debt shares to burn and to update the total debt and total spendable amount in the pool.
    /// @param from The address of the user or liquidator who is making the repayment.
    /// @param to The address to which the repayment amount will be transferred, which is typically the contract itself for regular repayments or the liquidator's address for repayments
    /// made during the liquidation process.

    function _repay(uint256 repayAmount, address from, address to) private {
        if (userDebtshare[from] == 0) {
            revert lendingPool_zeroDebtShares();
        }

        if (repayAmount > debtShareToWorth(userDebtshare[from])) {
            revert lendingPool_amountMoreThanDebt();
        }

        repayAmount = tokenTransfer(repayAmount, i_liquidityToken, to, address(this));
        uint256 borrowerDebt = debtShareToWorth(userDebtshare[from]);

        uint256 shareToBurn;

        if (repayAmount == borrowerDebt) {
            shareToBurn = userDebtshare[from];
        } else {
            shareToBurn = worthToDebtShare(repayAmount, borrowerDebt, from);
        }

        totalSpendableAmount += repayAmount;
        totalDebt -= repayAmount;

        totalDebtShare -= shareToBurn;
        userDebtshare[from] -= shareToBurn;
    }

    /// @notice A private function to accrue interest on the total debt in the lending pool. The function calculates the interest based on the time elapsed since the last accrual, the total debt, and the interest rate. The accrued interest is added to the total debt and total pool asset, and the last accrual time is updated to the current block timestamp.
    /// @dev This function is called before certain actions such as borrowing, repaying, withdrawing collateral, and liquidating to ensure that the interest is up-to-date before any changes are made to the user's position or the pool's state. By accruing interest before these actions, the contract can
    /// maintain accurate accounting of the total debt and ensure that users are charged the correct amount of interest based on the time they have had an outstanding debt. The function calculates the interest based on a simple interest formula, where the interest is proportional to the total debt, the interest rate, and the time elapsed since the last accrual. This function is crucial for maintaining the financial integrity of the lending pool and ensuring that users are charged appropriately for borrowing from the pool.

    function accureInterest() private {
        uint256 timeElapsed = block.timestamp - lastAccuredTime;
        if (timeElapsed > 0 && totalDebt > 0) {
            uint256 interest = (totalDebt * RATE * timeElapsed) / (MAX_BPS * 365 days);
            totalDebt += interest;
            totalPoolAsset += interest;
        }
        lastAccuredTime = block.timestamp;
    }

    /// @notice A private function to check if a user's health factor is below the minimum threshold and revert if it is. The function calculates the health factor of the user and compares it to the minimum threshold defined in the contract. If the health factor is below the minimum, the function reverts with an error indicating that the user's health factor is weak.
    /// @dev This function is used to ensure that users maintain a safe health factor when interacting with the lending pool. It is called after certain actions such as withdrawing liquidity or collateral to check if the user's position is still safe after the action. If the health factor is below the minimum threshold,
    /// the function reverts to prevent the user from taking actions that would put their position at risk of liquidation. By enforcing a minimum health factor, the contract can help maintain the integrity of the lending pool and ensure that users are aware of the risks associated with their positions. This function is crucial for managing risk in the lending pool and ensuring that users maintain safe positions when interacting with the pool.
    /// @param user The address of the user for whom to check the health factor.

    function revertIfHealthFactorWeak(address user) private view {
        uint256 healthfactor = healthFactor(user);

        if (healthfactor < MIN) {
            revert lendingPool_weakHealthFactor();
        }
    }

    ///////////////////////////////////////////////////
    ///             getter functions               ///
    ///////////////////////////////////////////////////

    function getUserLiquidityShares(address user) external view returns (uint256) {
        return userLiquidityShares[user];
    }

    function currentInterest() external {
        accureInterest();
    }

    function getUserCollateralDeposit(address user) external view returns (uint256) {
        return borrowerCollateralDeposit[user];
    }

    function getUserDebtShare(address user) external view returns (uint256) {
        return userDebtshare[user];
    }

    function getTotalLiquidityShares() external view returns (uint256) {
        return totalLiquidityShares;
    }

    function getTotalPoolAsset() external view returns (uint256) {
        return totalPoolAsset;
    }

    function getTotalCollateralPool() external view returns (uint256) {
        return totalCollateralPool;
    }

    function getTotalDebt() external view returns (uint256) {
        return totalDebt;
    }

    function getTotalDebtShare() external view returns (uint256) {
        return totalDebtShare;
    }

    function getTotalSpendableAmount() external view returns (uint256) {
        return totalSpendableAmount;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return healthFactor(user);
    }

    function getLTV() external view returns (uint256) {
        return i_LTV;
    }

    function getCollateralTokenAddress() external view returns (address) {
        return collateralTokenAddress;
    }

    function getLiquidityTokenAddress() external view returns (address) {
        return i_liquidityToken;
    }

    function getPriceFeed() external view returns (address) {
        return i_priceFeed;
    }

    function getShareToWorth(uint256 share) external view returns (uint256) {
        return debtShareToWorth(share);
    }

    function getDebtWorthToShare(uint256 amount, uint256 borrowerDebt, address user) external view returns (uint256) {
        return worthToDebtShare(amount, borrowerDebt, user);
    }

    function getTotalLiquidityShare(address user) external returns (uint256) {
        return userLiquidityShares[user];
    }

    function getLpShareToWorth(uint256 share) external view returns (uint256) {
        return ShareToWorth(share);
    }

    function getAmountToCollateral(uint256 repayAmount) external view returns (uint256) {
        return amountToCollateral(repayAmount);
    }
}
