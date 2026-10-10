# Vendored dependencies

These sources are included as ordinary files, with no git submodules or build-time downloads. Only the production ERC-20 dependency closure is included from OpenZeppelin; forge-std is used solely for tests. Vendored upstream Solidity files are unmodified.

## OpenZeppelin Contracts 5.0.2

- Upstream tag: `OpenZeppelin/openzeppelin-contracts`, `v5.0.2`.
- Source archive: <https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2>
- Archive SHA-256: `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`.
- Location: `lib/openzeppelin-contracts/`.
- Included: `contracts/token/ERC20/ERC20.sol`, `contracts/token/ERC20/IERC20.sol`, `contracts/token/ERC20/extensions/IERC20Metadata.sol`, `contracts/utils/Context.sol`, `contracts/interfaces/draft-IERC6093.sol`, and `LICENSE`.
- License: MIT; full notice in `lib/openzeppelin-contracts/LICENSE`.

## forge-std 1.9.7

- Upstream tag: `foundry-rs/forge-std`, `v1.9.7`.
- Source archive: <https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7>
- Archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`.
- Location: `lib/forge-std/`.
- Included: the complete `src/` directory plus `LICENSE-APACHE` and `LICENSE-MIT`.
- License: Apache-2.0 or MIT; both notices are included.

The Foundry toolchain and the Solidity compiler are checker prerequisites, not Solidity dependencies. No compiler binaries are vendored or path-pinned.
