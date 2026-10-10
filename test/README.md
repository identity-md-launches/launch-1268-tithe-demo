# Tithe Demo tests

Run the complete local suite with `forge build` and `forge test`. All dependencies
are already vendored; these tests use no RPC, fork, environment changes, or downloads.

The expected issuance is independently fixed at `1_000_000_000 * 10 ** 18` base
units. Expected balances are never initialized from the token's reported supply.

| Suite | Properties checked |
| --- | --- |
| `TitheDemo.t.sol` | Metadata, constructor mint and event, immediate factory ownership, exact transfers, approvals, finite and infinite spending, invalid addresses, insufficient balances/allowances, unavailable admin entry points, runtime restrictions, modeled launch custody movements. |
| `TitheDemo.edge.t.sol` | One base unit, maximum amounts, largest finite approval, repeated and competing spends, allowance reduction, infinite-to-finite replacement, owner-as-spender, zero-value delegated events, and invalid zero-value operations. |
| Edge fuzz properties | Round trips between funded holders, split versus single delegated spending, isolated and idempotent approval replacement, retry after insufficient funds without reapproval, excessive self-transfers, and transfers to the token's own address. |
| `TitheDemo.invariant.t.sol` | Fixed supply, complete balance sum, each holder's exact expected balance, and all actor-pair allowances after random valid and rejected operations. |

The unit/fuzz suites contain 49 test functions, including 10 fuzz properties at
1,000 cases each. The invariant suite declares four invariants and runs 256
sequences of 128 handler calls. Counts and failure-on-revert behavior are declared
inline in the Solidity tests without changing repository configuration.

The stateful handler keeps all tokens among four actors, including the contract
deployer. It updates an independent ledger from requested transfers and approvals.
It deliberately includes zero, one base unit, full available balances, arbitrary
amounts, self-transfers, self-approvals, revocation, and finite/infinite approvals.
All 16 owner/spender pairs are checked, including pairs uninvolved in the last call.
Supply conservation alone would miss transfers credited to the wrong holder;
the per-holder ledger detects those as well.

Rejected calls cover excessive transfers, excessive delegated spends, insufficient
balance despite sufficient approval, zero receivers, and zero spenders. They must
revert with the expected ERC-6093 error. The ledger does not change for a rejected
call, so subsequent invariant checks require balances and approvals to be intact.
Unexpected reverts fail the campaign. Call statistics in `forge test` show which
handler actions were exercised; these statistics count expected, checked token
reverts as successful handler calls.

The supplied protected launch check requires platform contracts and resolved
launch inputs that are not present in this repository. The local custody-flow
test does not execute Uniswap pool initialization or swaps. That integration
remains the responsibility of the separate protected launch harness.
