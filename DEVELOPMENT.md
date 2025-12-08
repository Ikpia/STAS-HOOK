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
