# STAS Hook

**Smart Threshold-Activated Stability Hook for Uniswap V4**

## Problem Statement
Stablecoin pools like USDC/USDT are designed to stay at 1:1, but they often suffer from depegging during market stress. 
Factors such as confidence issues, liquidity imbalance, and arbitrage lead to deviation from parity, creating risks for liquidity providers and unfair outcomes for users.

## Solution
STAS Hook introduces a mechanism that integrates real-world price feeds using Pyth oracles and dynamically adjusts market fees based on pool conditions.
- When trades worsen the depeg, higher fees are applied to discourage further imbalance.
- When trades help stabilize the peg, lower fees are applied as an incentive.  
This ensures a self-balancing system that protects liquidity providers and encourages users to act in the best interest of the pool.

## Benefits

### For Liquidity Providers (LPs)
- Reduces exposure to impermanent loss caused by arbitrage during depeg events.
- Protects liquidity depth by penalizing harmful trades.
- Encourages long-term stability of the pool.

### For Users
- Dynamic fee structure rewards users who help restore balance in the pool.
- Provides fairer trading conditions during market volatility.
- Builds trust by aligning incentives with system stability.

## Setting Things Up

### Install Dependencies
```bash
forge install
npm install
```

### Run Tests
```bash
forge test --fork-url https://ethereum-rpc.publicnode.com -vvvvv
```

## Project Vision
STAS Hook aims to provide a dynamic, oracle-driven stabilization mechanism for stablecoin pools, improving resilience during stressful events while protecting both LPs and users.
