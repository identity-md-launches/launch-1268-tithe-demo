# Tithe Demo (TDEMO)

TDEMO is an immutable, fixed-supply ERC-20. Its constructor mints **1,000,000,000 tokens with 18 decimals** to the immediate deployer, once. The complete supply in smallest units is **1000000000000000000000000000** (`10^27`).

## Contract and assumptions

The deployable contract is [`src/TitheDemo.sol`](src/TitheDemo.sol), Solidity identifier `TitheDemo`. It inherits the vendored OpenZeppelin Contracts 5.0.2 ERC-20 implementation without changing transfer behavior.

- Name: `Tithe Demo`; symbol: `TDEMO`; decimals: `18`.
- The brief specifies no transfer tax or tithe mechanism. Transfers deliver the exact requested amount, including through a factory, distributor, or pool.
- There is no owner, minter, burn function, blacklist, pause, seizure, upgrade, proxy, or initializer. The deployer has ordinary holder rights after construction.
- `transfer`, `approve`, and `transferFrom` return `true` on success and revert with ERC-6093 custom errors on invalid operations. Zero-value transfers between valid addresses and self-transfers are supported. Transfers to the zero address and approvals to a zero spender revert.
- Approvals replace the previous allowance. Finite allowances decrease when spent; `type(uint256).max` remains unchanged when spent and can still be revoked. Only an approved spender may use `transferFrom`, including when the caller is the deployer or the source account itself.
- Construction emits one `Transfer` from the zero address for the full supply. Transfers emit `Transfer`; explicit approvals emit `Approval`. This OpenZeppelin version does not emit `Approval` when `transferFrom` spends an allowance; indexers must query `allowance` for current values.
- No external calls, callbacks, oracle, time dependency, or network-specific address is involved in the token. It can deploy on an otherwise empty chain.

## Build and verification

Install Foundry and Solidity **0.8.26** in the checking environment. All Solidity dependencies are ordinary vendored source files in `lib/`; no dependency install, submodule, RPC, wallet, environment variable, or network request is needed to build or test once the pinned compiler is installed.

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimizer at 200 runs, and `bytecode_hash = "none"`. It enables neither FFI nor filesystem permissions. Ethereum supports this EVM target.

The test suite covers metadata and exact issuance, the mint event, factory CREATE2 deployment, exact transfers and events, zero/self/full-balance transfers, contract recipients, allowance replacement/revocation, finite/infinite allowance spending, insufficient balance/allowance, invalid recipients, transaction rollback, and unavailable mint/burn/admin calls. Four fuzz tests exercise transfer accounting and invalid spends across amounts. Two stateful invariants exercise arbitrary sequences of transfers, approvals, and delegated transfers and check supply conservation and the sum of all holder balances. Defaults are 512 cases per fuzz test and 256 sequences of 64 calls per invariant.

The launch-flow test models custody transfers for the 10% distributor, 88% pool allocation, and 2% remainder, subsequent claims, and token movements to/from pool custody. It does **not** instantiate Uniswap or validate pricing, liquidity, or swaps. The supplied protected launch harness belongs to the separate launch verifier and needs its platform contracts and resolved launch inputs; it is not part of the local test suite.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Contract artifact | `out/TitheDemo.sol/TitheDemo.json` |
| Solidity identifier | `TitheDemo` |
| Constructor arguments | None (`[]`) |
| Transaction value | `0` ETH |
| Supply in smallest units | `1000000000000000000000000000` |
| Initial recipient | Immediate constructor caller (`msg.sender`) |
| External library links | None |
| Post-deployment initialization | None |

Build the creation bytecode with `forge inspect src/TitheDemo.sol:TitheDemo bytecode`. The authorized launch system deploys that creation bytecode directly through its factory. With CREATE or CREATE2, the **factory** receives the whole supply; neither the factory's caller nor `tx.origin` receives a constructor allocation. A direct deployment instead gives the supply to its direct deployer. A wrapper contract must be capable of forwarding its allocation; using one changes who initially holds the tokens.

This assignment's launch is on Ethereum (chain ID 1), paired with IMD at `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`. The launch system is responsible for the distributor and pool, using the supplied pool fee `12500` (1.25%), tick spacing `60`, and provenance price `79228162514264337593543950336`. That pool fee is external to TDEMO transfers. The launch system derives the opening price from the supply, token address, and the requested initial market cap of `2500000000000000000000` IMD minor units (2,500 IMD).

The factory handles the 10% swarm distribution and requested economics: `poolBps = 8800` and `remainderTo = 0x6bf192ebef135e0f645e99d59d9bf44e7711606c`. No allocations or exemptions are embedded in this token, and no application contracts are required. The platform creates `launch.json` in its separate manifest step. This project supplies no manifest, deployment key, or broadcast script.

## After launch

There are no owner-settable settings or maintenance transactions. The authorized deployer must verify the deployed runtime against the pinned build, verify source on the explorer, confirm name/symbol/decimals, total supply and the constructor mint recipient, and check the factory's distribution and actual pool operations. The separate launch review must execute the protected integration checks with the resolved launch parameters.

Holders control their tokens and allowances. Use deliberate spender approvals, revoke unused approvals, and set an existing allowance to zero and confirm that transaction before replacing it with a new nonzero allowance when a spender might race the change. Unlimited approvals expose the holder's available balance to the spender until revoked. Contracts receiving TDEMO must provide their own withdrawal or forwarding logic; this token has no recovery facility for mistaken transfers or assets sent to its own address. It has no payable entry point.

Local unit, fuzz, and invariant tests support review but are not an independent security audit. Independent adversarial review remains a release responsibility. Slither and Mythril were not run. No on-chain transaction was sent as part of this work.

Dependency versions, included files, source archives, checksums, and licenses are recorded in [`DEPENDENCIES.md`](DEPENDENCIES.md).
