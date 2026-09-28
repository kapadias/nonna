# Architecture Decision Records

Architecture Decision Records (ADRs) capture significant, hard-to-reverse decisions — the context, the
options weighed, the choice, and what it costs. They live here, numbered and immutable; supersede
rather than edit.

| #    | Title                                                                                               | Status                                       | Date       |
| ---- | --------------------------------------------------------------------------------------------------- | -------------------------------------------- | ---------- |
| 0001 | [Record architecture decisions](0001-record-architecture-decisions.md)                              | Accepted                                     | 2026-06-22 |
| 0002 | [The LLM proposes; deterministic gates decide](0002-llm-proposes-gates-decide.md)                   | Accepted                                     | 2026-06-22 |
| 0003 | [Progressive disclosure for the token economy](0003-progressive-disclosure-token-economy.md)        | Accepted                                     | 2026-06-22 |
| 0004 | [Gates as code, not prose](0004-gates-as-code.md)                                                   | Accepted                                     | 2026-06-23 |
| 0005 | [Machine-checkable review verdict](0005-machine-checkable-review-verdict.md)                        | Accepted                                     | 2026-06-23 |
| 0006 | [Distribute Nonna as a plugin (zero-duplication)](0006-distribute-as-plugin.md)                     | Accepted; component claim superseded by 0007 | 2026-06-23 |
| 0007 | [A plugin install is not equivalent to a copy-in install](0007-plugin-install-is-not-equivalent.md) | Accepted                                     | 2026-08-01 |
| 0008 | [A decision ladder for solution size](0008-decision-ladder-for-solution-size.md)                    | Accepted; "no lighter mode" amended by 0011  | 2026-09-22 |
| 0009 | [Proportional review, sized by script](0009-proportional-review.md)                                 | Accepted                                     | 2026-09-24 |
| 0010 | [The harness is Nonna](0010-the-harness-is-nonna.md)                                                | Accepted                                     | 2026-09-24 |
| 0011 | [Lite mode and plugin defaults](0011-lite-mode-and-plugin-defaults.md)                              | Accepted; amends 0007 and 0008               | 2026-09-25 |

New ADRs are added with the **`/adr`** skill, which scaffolds the next number from the Nonna template
and updates this index.
