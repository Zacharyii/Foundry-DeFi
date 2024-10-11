# Stablecoin Implementation

设计开发稳定币的铸造合约代码编写，用户可以存款WETH或WBTC，换取和美元相关的代币。

## Stablecoin Features

1. **Relative Stability: Anchored or Pegged**
   - Utilizes Chainlink price feeds.
   - Includes functions to exchange ETH and BTC for USD.

2. **Stability Mechanism (Minting): Algorithmic (Decentralized)**
   - Users can only mint stablecoins if they provide sufficient collateral.

3. **Collateral: Exogenous (Crypto)**
   - Accepts wETH (Wrapped Ether).
   - Accepts wBTC (Wrapped Bitcoin).

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
