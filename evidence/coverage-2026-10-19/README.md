# Current-public-suite production coverage — fun

Generated **19 October 2026**, from public source/test commit `385cc197dc507521c395fea860e1505a8832cedc`.
Deployed package: `0x96e1396c8a771c8ae404b86328dc27e7b66af39847a31926980c96dbc1096a15`, version 1.

**All 32 published tests passed; 32/32 per-test traces verified. No test filter or test exclusion was used.** This supersedes the older October 14 coverage snapshot for this current public test tree.

## Results

- Production line coverage: **39.59%** (156/394).
- Production CFG-edge branch coverage: **21.36%** (22/103).
- Production function coverage: **57.14%**.

| Production file | Lines hit/found | CFG edges hit/found | Functions hit/found |
|---|---:|---:|---:|
| sources/curves.move | 0/16 | 0/0 | 0/3 |
| sources/full_math_u64.move | 17/17 | 0/0 | 6/6 |
| sources/turbospump.move | 139/361 | 22/103 | 10/19 |

## Scope and verification

Coverage excludes dependencies, test modules, inline tests and test-only helpers, using the normal non-test build's function inventory. Root-module source-map line denominators are checked against official Sui LCOV before excluding test code. Zero-hit production functions/lines remain in the denominator. Branch coverage is the official Sui CFG-successor-edge metric, which includes unconditional edges; it is not a decision-only percentage.

The tested source/tests have SHA-256 tree digest `a0d56e5eea0a3f6be8374f914cdfd7af999d7359f7a3a13d710e560763c25d1b`, matching the October 15 public test baseline. The normal-build root module hashes still match the previously recorded immutable deployed-module hashes; this does not claim a fresh chain fetch or separate dependency-bytecode audit. No production contract changes or mainnet transactions were made.

Full tracing and LCOV generation used the checksum-verified official macOS arm64 CLI.

## Evidence

- [Production coverage JSON](production-coverage.json), [production-only LCOV](production-lcov.info), [raw test-build LCOV](raw-lcov.info).
- [Run/trace-count verification](run.json), [full test log](traced-tests.log), [instruction summary](instruction-summary.log), [LCOV-generation log](lcov-generation.log).
- [Exact source/test hashes](source-hashes.json), [normal-build functions](normal-build-functions.json), [deployed-bytecode reference comparison](normal-bytecode.json).
- [Official CLI archive checksum/provenance](release-download.json). Absolute workspace source paths are normalized in public artifacts; counts and identifiers are unchanged. Raw value traces are not published.

## Reproduce

Use Node.js 22+ and official tracing-enabled Sui **1.66.2-a9a6825eaf62**. CLMM/Vault full tracing currently overflows the stock CLI on both macOS and Linux; their reports and explicit partial-mode instructions document that limitation. Obtain the appropriate official archive from https://github.com/MystenLabs/sui/releases/tag/mainnet-v1.66.2 and verify its published archive checksum.

Run at this repository's root:

```sh
SUI_BINARY=/absolute/path/to/tracing/sui node tools/coverage-current.mjs /tmp/turbos-fun-coverage-current
```

The destination must not exist. The script copies the current checkout into disposable normal-build/test workspaces, pins the test framework to the CLI's recorded native interface, checks normal-build module hashes against the deployment reference, runs the full expected suite with per-test trace checks, and generates official LCOV plus production-only results. No old test overlay is applied. The five-GiB free-disk guard and per-step timeout stop failed runs without labelling them successful. No wallet or keystore is accessed.

## What this does not claim

Full-suite collection means every currently published test was measured, **not** that every production line, branch, authorization check or invariant has a test. The remaining zero-hit lines/functions are listed in the JSON; further positive/negative authorization and invariant tests remain a separate task. These results are not a declaration of exhaustive testing or compliance closure. Historical coverage snapshots remain available.
