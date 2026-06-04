
---

# LendingPool

A lending protocol built after learning from bugs in my first attempt and completing the Cyfrin Updraft stablecoin course.

## Overview

The LendingPool protocol allows users to:
- Deposit liquidity (USDC) to earn yield
- Deposit collateral (WETH) to secure loans
- Borrow USDC against their collateral
- Repay debt with accrued interest
- Withdraw liquidity or collateral
- Liquidate undercollateralized positions

The system is built around share-based accounting and health factor calculations to maintain protocol solvency.

## My Journey

### CapLendingProtocol (First attempt)
I built this when I was first learning Solidity. Looking back, it had bugs:
- Decimal handling issues (USDC 6 decimals vs WETH 18 decimals mixed incorrectly)
- No reentrancy protection
- Share price manipulation vulnerability
- Complex fee logic that wasn't fully tested

The code is still on GitHub. I keep it there to remind myself where I started.

### Decentralized Stablecoin (Cyfrin Updraft course)
This course taught me:
- Health factor calculations
- Chainlink price feed integration
- Liquidation mechanics
- Collateralized debt positions (CDPs)
- Invariant testing
- Protocol accounting

### This project (LendingPool)
Using what I learned from both projects, I rebuilt the lending protocol with:
- ReentrancyGuard on all state-changing functions
- Proper decimal handling using constants
- Debt shares separate from liquidity shares
- Health factor enforcement
- Balance-before/after pattern for fee-on-transfer tokens

## Features

### Deposit Liquidity
Users deposit USDC and receive liquidity shares. The share price increases as the pool earns interest from loans.

### Deposit Collateral
Users deposit WETH as collateral. The protocol tracks collateral values using Chainlink price feeds.

### Borrow
Users can borrow USDC against their collateral. The maximum borrow amount is limited by the loan-to-value (LTV) ratio.

### Repay
Users repay debt plus accrued interest. Interest accrues over time based on a fixed annual rate.

### Withdraw Liquidity
Users burn their liquidity shares to withdraw USDC from the pool.

### Withdraw Collateral
Users can withdraw collateral as long as their health factor remains above the minimum threshold.

### Liquidate
When a user's health factor falls below 1, anyone can liquidate the position. The liquidator repays part of the debt and receives collateral plus a 10% bonus.

## Architecture

### Core Contracts

**LendingPool.sol**
Main protocol contract responsible for:
- Liquidity deposits and withdrawals
- Collateral deposits and withdrawals
- Borrowing
- Repayment
- Liquidations
- Interest accrual
- Health factor calculations

**Oracle.sol**
Provides price feed integration with stale-price protection.

### Key Data Structures

```solidity
mapping(address => uint256) public userLiquidityShares;
mapping(address => uint256) public borrowerCollateralDeposit;
mapping(address => uint256) public userDebtshare;
```

### Health Factor

A position is considered healthy when:
```
Health Factor >= 1
```

A position becomes eligible for liquidation when:
```
Health Factor < 1
```

The health factor is calculated using:
- Collateral value (in USD)
- Loan-to-value ratio
- Outstanding debt

## Testing

The project includes:

- 27 unit tests covering all core functions
- Invariant tests (3 core properties)
- Handler for stateful fuzzing
- Edge case testing (zero amounts, invalid addresses, health factor boundaries)

### Run tests

```bash
forge test
forge test --gas-report
forge test --match-contract lendPoolOpenInvariantTest -vvv
```

### Invariants verified

1. `totalPoolAsset == totalSpendableLiquidity + totalDebt`
2. `totalSpendableLiquidity == actual protocol USDC balance`
3. `totalCollateralPool == actual protocol WETH balance`

## Tech Stack

- Solidity ^0.8.18
- Foundry
- OpenZeppelin Contracts
- Chainlink Price Feeds

## Deployment

```bash
forge script script/LPoolDeployScript.s.sol --rpc-url $RPC_URL --private-key $KEY --broadcast
```

## Known Limitations

These are features I know are missing and plan to add:

- Max borrow limits per user
- Emergency pause mechanism
- Multi-collateral support
- Dynamic interest rates
- Flash loan attack protection

## What I Learned

Building this project after the stablecoin course helped me understand:

- How share-based accounting works for liquidity pools
- Why debt shares need to be separate from liquidity shares
- How interest accrual affects both borrowers and liquidity providers
- The importance of invariant testing in DeFi protocols
- How to structure a lending protocol safely

## Future Plans

My next steps:

1. Add max borrow limits
2. Implement emergency pause
3. Add multi-collateral support
4. Get the code professionally audited

## Author

Daniel Adu

Currently focused on:
- Solidity Development
- DeFi Protocol Building
- Foundry Testing
- Smart Contract Security

## Disclaimer

This project was built for learning purposes. It has not been professionally audited. Do not use with real funds without thorough testing and security review.

## Links

- [First attempt (has bugs)](https://github.com/Adud09/cap-lending-protocol)
- [Stablecoin project (Cyfrin course)](https://github.com/Adud09/DecentralisedStableCoin)
- This repo

## License

MIT

---

*Built after learning from mistakes. Still learning.*