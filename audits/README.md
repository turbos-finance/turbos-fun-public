# Audit evidence - Turbos Fun

The original [MoveBit report](movebit-fun-2024.pdf) is preserved without modification.

| Item | Evidence |
|---|---|
| Auditor | MoveBit (individual reviewer names not disclosed in the report) |
| Review period | 2024-10-10 through 2024-10-16 |
| Reviewed revisions | `d0c0ef13cc319696de9b605b3245ee70f96133a3`, `662821f6fd721f89fe496dcdee3fbb5cc1408e53` |
| Scope | `curves`, `full_math_u64`, `turbospump`; report section 1.2 contains file hashes |
| Method | Architecture review, unit testing and manual review; methodology in section 1.5 |
| Findings | 8: 1 major, 3 medium, 3 minor, 1 informational; all marked fixed by the report |

Both original commits are available in this repository's Git history. Fixes are visible
in `6677d339cbc3ff1fc3706bfdb00306766096909b` and
`662821f6fd721f89fe496dcdee3fbb5cc1408e53` (the latter explicitly addresses TUR-2/TUR-5).
Individual issue descriptions and their reported disposition remain in the PDF; no
independent auditor sign-off beyond that report is implied.

## Deployed-source delta

The deployed revision is `7a5f81eeff29ec6baf53ee36dc84f512fb8c663d`, not the last audit
revision. `turbospump.move` changed by 104 insertions and 28 deletions afterward,
including graduation work. This audit is historical coverage, not proof of a complete
audit of the deployed revision. A delta review and a complete finding-to-fix matrix
must be supplied before claiming the latest audit-quality requirement closed.
