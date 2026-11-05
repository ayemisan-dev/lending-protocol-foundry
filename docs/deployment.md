# LendX Deployment Record

## Network

- **Network**: Ethereum Sepolia
- **Chain ID**: 11155111
- **Deployer**: `0x4b23E21C1011003B22E7FAB0cc937408Dc404F5E`

## Deployed Contracts

| Contract         | Address                                      | Etherscan                                                                                   |
| ---------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------- |
| ProtocolConfig   | `0x8388c77999ebB82D53D4997CFE8e6cACDEA9A43e` | [Verified](https://sepolia.etherscan.io/address/0x8388c77999ebB82D53D4997CFE8e6cACDEA9A43e) |
| OracleReader     | `0x9b19CD6b433E9B151c2f11a174f72808B979d59d` | [Verified](https://sepolia.etherscan.io/address/0x9b19CD6b433E9B151c2f11a174f72808B979d59d) |
| LendingPool      | `0xeC8de0C9E429652F7541BD313cA51e944277aFB8` | [Verified](https://sepolia.etherscan.io/address/0xeC8de0C9E429652F7541BD313cA51e944277aFB8) |
| RiskEngine       | `0xEF6194e4C2B22d11008dD45424309eD4994c6F53` | [Verified](https://sepolia.etherscan.io/address/0xEF6194e4C2B22d11008dD45424309eD4994c6F53) |
| TestToken (tUSD) | `0xBCFf6dA2f6e00B66655954C87d6894cBa33777c7` | [Verified](https://sepolia.etherscan.io/address/0xBCFf6dA2f6e00B66655954C87d6894cBa33777c7) |
| TestFeed         | `0xF340ef2988A635B0789304EE182A29bC34EF36D8` | [Verified](https://sepolia.etherscan.io/address/0xF340ef2988A635B0789304EE182A29bC34EF36D8) |

## Asset Configuration

- **Asset**: tUSD (MockERC20)
- **LTV**: 8000 BPS (80%)
- **Liquidation Threshold**: 8500 BPS (85%)
- **Liquidation Bonus**: 500 BPS (5%)
- **Price Feed**: MockAggregatorV3 (8 decimals, initial answer 1e8 / $1.00)

## Deployment Order (Load-Bearing)

Deployment must follow this order due to one-time binding constraints:

1. `ProtocolConfig(owner)`
2. `OracleReader(owner, maxPriceAge)`
3. `LendingPool(owner)`
4. `pool.setProtocolConfig(config)`
5. `RiskEngine(config, oracle, pool)`
6. `pool.setRiskEngine(engine)` — validates engine references this pool and config.
7. `config.configureAsset(...)`
8. `oracle.setPriceFeed(...)`

## Reproducing the Deployment

### Prerequisites

- `.env` with `SEPOLIA_RPC_URL`, `PRIVATE_KEY`, `ETHERSCAN_API_KEY`.
- Deployer wallet funded with Sepolia ETH.

### Command

```bash
forge script script/Deploy.s.sol:DeployLendX \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --gas-estimate-multiplier 1000 \
    --slow
```

### Engineering Note on Gas Estimation

Foundry 1.8.5 with via_ir = true systematically underestimates gas for contract creation. Without --gas-estimate-multiplier, deployments fail with "contract creation code storage out of gas" on Sepolia, despite bytecode being well within EIP-170 limits. The multiplier of 1000 ensures the code deposit phase succeeds. Actual gasUsed remains low; unused gas is refunded.

### Smoke Test

A post-deployment smoke test verified full protocol functionality on Sepolia:

```bash 
forge script script/SmokeTest.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

On-chain state confirmed: supplied = 1000e18, borrowed = 100e18.

---