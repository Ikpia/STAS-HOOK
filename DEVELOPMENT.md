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
- Uses BaseOverrideFee hook pattern
- Implements afterInitialize and beforeSwap hooks
### Pyth Network
- Real-time price feeds for both pool tokens
- Confidence interval validation
## Constants Reference
### Threshold Values
- VOLATILE_THRESHOLD: 100 bps (1%)
- DEPEG_THRESHOLD: 50 bps (0.5%)
### Fee Limits
- MAX_PENALTY_FEE: 50000 bps (5%)
- MIN_STABILIZE_FEE: 500 bps (0.05%)
## Access Control
### Roles
- ADMIN_ROLE: Full administrative access
- PAUSER_ROLE: Ability to pause contract
- CONFIG_ROLE: Configuration management
