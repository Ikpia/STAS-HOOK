# DepegSentinel Development Log
## Architecture Overview
### Core Components
- DepegPenaltyHook: Main hook contract
- PythOracleAdapter: Oracle price feed adapter
## Testing Strategy
### Test Coverage
- Depeg penalty application tests
- Stabilization reward tests
- High confidence scenario tests
## Deployment Guide
### Prerequisites
- Foundry installed
- Node.js and npm installed
- Access to Pyth Network oracle
## Security Considerations
### Oracle Reliability
- Pyth Network provides high-frequency price updates
- Confidence thresholds prevent volatile price usage
## Fee Calculation Logic
### Penalty Fees
- Applied when trades worsen depeg conditions
- Scales with depeg severity
- Capped at MAX_PENALTY_FEE (5%)
### Stabilization Rewards
- Lower fees for trades that restore peg
- Minimum fee floor at MIN_STABILIZE_FEE (0.05%)
## Integration Points
### Uniswap V4
