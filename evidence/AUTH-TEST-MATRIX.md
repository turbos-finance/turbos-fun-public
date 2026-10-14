# First authorization/invariant test batch — Turbos Fun

Pinned deployed source: `7a5f81eeff29ec6baf53ee36dc84f512fb8c663d`.
[Results](tests-security-2026-10-14.json): **20 passed, 0 failed**.
[Full output](tests-security-2026-10-14.log), [before-overlay baseline](tests-before-overlay-2026-10-14.json).

## Explicit test changes

The original tests file is fully commented out (0 runnable tests). Adds 20 inline tests and test-only fixtures, exercising capability ownership, configuration/version checks, fee balance accounting and completed/incomplete pool migration/collection/skim. Synthetic Pool<SUI> fixtures do not model bonding-curve trading or real CLMM liquidity creation.

The source anchors and production functions are untouched in this repository. The test
patch/new files are versioned under tools/repro and applied only in a disposable test
checkout. Normal build mode never applies the overlay. No mainnet transaction is needed.

A separate normal build after the overlay still matches every deployed root module BCS byte: [result](test-overlay-bytecode-2026-10-14.json).

## Test mapping and remaining scope

| Control | Positive case | Negative case |
|---|---|---|
| Admin configuration / payout | security_admin_can_update_configuration; security_admin_can_set_payout_destination | stale/future version tests |
| Version migration | security_admin_can_migrate_stale_version | current/future migration rejection |
| Capability custody (Sui input model) | security_cap_transfer_changes_its_holder_not_payout | security_non_owner_cannot_take_admin_cap |
| Fee withdrawal accounting | capped-to-balance / partial collection tests | security_fee_collection_rejects_wrong_version |
| Graduating pool migration | completed pool returns all reserves | security_incomplete_pool_rejects_migration |
| Pool collection | completed pool preserves remainder | security_incomplete_pool_rejects_collection |
| Migration event | completed pool can emit event | security_incomplete_pool_rejects_migration_event |
| Skim payout | configured destination, not cap holder | security_incomplete_pool_rejects_skim |

The capability negative case tests scenario input ownership, not an entry-specific sender
ACL. Configuration.admin is a payout destination, not the AdminCap holder. Synthetic
fixtures do not cover token creation, buy/sell curves, slippage, LP invariants, all parameter
bounds or actual cross-package graduation. pool_migrated has no version check in the
deployed source; these tests do not establish that every public function is version gated.

## Re-run

Install the pinned CLI from REPRODUCE-LATEST.md, then:

```bash
cd tools/repro
npm install --ignore-scripts
node reproduce.mjs /tmp/turbos-fun-security-tests test
```

The path must not exist. Framework native functions are aligned with the CLI; VM test
budget is 1,000,000,000, not a mainnet gas payment.

A separate official tracing-enabled CLI now supplies a
[production-only coverage report](coverage-2026-10-14/README.md). Its precise full/partial
tracing scope is disclosed there; this original passing test baseline remains unchanged.
The complete every-auth/every-invariant matrix is still required. R10 is not closed.
