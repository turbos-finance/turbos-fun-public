# Turbos Fun - deployed source

This repository publishes the Move contract and existing tests for mainnet package
`0x96e1396c8a771c8ae404b86328dc27e7b66af39847a31926980c96dbc1096a15` (package version 1).

The deployed source revision is
[`7a5f81eeff29ec6baf53ee36dc84f512fb8c663d`](https://github.com/turbos-finance/turbos-fun-public/tree/7a5f81eeff29ec6baf53ee36dc84f512fb8c663d).
Contract sources and existing tests are unchanged from that revision. Later uncommitted
development changes have not been included.

See [source provenance](evidence/source-provenance.json), [build verification](evidence/build-verification.json),
[audit evidence](audits/README.md), and [security contact](SECURITY.md).

## Architecture

`turbospump` manages configuration, bonding-curve pools, trading and graduation.
`curves` and `full_math_u64` provide curve and arithmetic support.
Graduation returns assets for subsequent CLMM liquidity creation within a PTB.
The AdminCap gates privileged operations; `Configuration.admin` is a payout destination.

## Reproduction

Use the original deployed revision above and Sui CLI 1.32.1, as recorded in `Move.lock`.
For deterministic dependency resolution, use Sui framework revision
`624300d58deda9aea058f2dac58bdfab1a87e13f` (testnet-v1.32.1), instead of today's mutable
`framework/testnet` branch. Pin `published-at` to the package above and the `turbospump`
named address to the original package address before verification.

```sh
sui move build
sui move test
sui client verify-source
```

The archived verification result was obtained on 2026-09-29. A new verifier must record
its exact compiler and dependency revisions; a different framework/compiler may change
bytecode. Line and branch coverage reports have not yet been published.

## Current-release metadata verification (2026-10-15)

See [verified build configuration and official source-verification evidence](evidence/mvr-source-2026-10-15/README.md). This update does not change production functions. MVR GitInfo update and a fresh-cache registry-consumer run are separate follow-ups.
