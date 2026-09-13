## Description

`seed/CONVENTIONS.md` gains one rule — a read that could not have established the answer returns UNKNOWN — with its four measured corollaries, referenced from the launcher, the tick and the eval case that grades it, and pinned by a harness so it cannot be thinned.

Verified: `unverified-read-is-unknown.test.sh` 65/0 locally plus 23 sibling harnesses green, and `harness suite` green on [run 34396107023](https://github.com/cbmono/ai-bridge/actions/runs/34396107023).

### Criteria (8 ✓ / 0 ✗)

| Criterion | ✓ | Verified by |
|---|---|---|
| CONVENTIONS.md gains the rule, stated on what the read could not have established — not on whether it errored | ✓ | `unverified-read-is-unknown.test.sh` §1, 6/0 |
| all four measured corollaries ship as its examples (empty string, superseded, no pod, matcher) | ✓ | same harness §2, 10/0 |
| each example states what the read returned and what it could not have established | ✓ | §2 asserts both halves of all four rows |
| referenced from project-manager.md, dispatch/SKILL.md and the role-agent contract | ✓ | §4, 5/0; mutation D flips it |
| seed placement justified in the shipped text by the independent reinvention | ✓ | §3, 8/0; mutation C flips it |
| a harness asserts the rule and its four examples | ✓ | `bash tests/unverified-read-is-unknown.test.sh` 65/0, 5 mutation arms |
| cross-referenced both ways to task 8 eval case 2 and task 9 rule 1 | ✓ | §5, 6/0; mutation E flips the back-ref |
| no version change inside the PR | ✓ | `git diff --numstat origin/main` names no VERSION file |

### Notes

- **The four examples are the rule's payload, not decoration** — mutation B deletes only the table and requires all eight halves to flip, because the abstract form is already believed by everyone who then breaks it.

⚠️ Needs your call: `seed-size.test.sh` ceiling 14622 → 14737 (+115 bytes), for the back-reference criterion 7 requires in `seed/CLAUDE.md`.


<!-- This is an auto-generated comment: release notes by coderabbit.ai -->

## Summary by CodeRabbit

* **Documentation**
  * Added guidance requiring inconclusive reads to be reported as `UNKNOWN`, including the follow-up read needed to resolve them.
  * Documented examples covering image digests, checks, pod availability, and workflow matching.
  * Clarified launcher and project-manager behavior for unresolved rollout, check, region, and workflow questions.
  * Added cross-references connecting the guidance to relevant evaluations.

* **Tests**
  * Added regression coverage to verify the new guidance, examples, rationale, and cross-references remain intact.

<!-- end of auto-generated comment: release notes by coderabbit.ai -->
