# Recorded reviewer artifacts

Verbatim comment bodies fetched from real pull requests on this repository with
`gh pr view <n> --json comments --jq '.comments[0].body'`. They are **evidence, not
samples** — do not tidy, shorten, or re-wrap them. `tests/review-clearance.test.sh`
drives the classifier against exactly what the reviewer published.

| File | Source | The shape it pins |
|---|---|---|
| `clean-review.pr29.md` | PR #29, head `8f40f2e` | a real review — "No actionable comments were generated in the recent review" |
| `rate-limit-refusal.pr30.md` | PR #30, head `88c106a` | a REFUSAL published behind a green status check — "Review limit reached. Next included review available in 44 minutes" |

The third shape the tests cover — **no reviewer signal at all** — needs no fixture:
it is the absence of these files, and the test constructs it as an empty artifact list.

## Why the refusal fixture is the important one

Both files contain the line

> Reviewing files that changed from the base of the PR and between `<base>` and `<head>`.

and in **both** the `<head>` is the PR's real head SHA. So the commit range is
identical in shape between a review and a refusal, and a detector that keys on it
reads "Review limit reached" as clearance. On #30 that is exactly what happened: it
merged unreviewed and shipped a shell script at mode `100644`. Only the refusal
*language* separates the two files, which is why the classifier tests language first
and the head second.

## Two properties of these files that the tests assert before relying on them

Both are the kind of thing that goes quietly untrue when a vendor rewords, at which point
every assertion built on them passes vacuously. So they are asserted, not assumed.

1. **The refusal carries the machine-readable `rate limited by coderabbit.ai` sentinel
   and NO review-evidence marker** — no walkthrough, no actionable-comment count. That
   matters because the refusal quotes the PR head: if review evidence could outrank the
   sentinel, this exact file would clear.
2. **Neither file contains a code fence.** So every fence case in the tests is
   constructed — including the one-character bypass they exist for, which is this refusal
   with a single ` ``` ` prepended.

A third shape is deliberately *not* a fixture here, because it is a count rather than a
body: on this repository **18 of 35 pull requests carry a CodeRabbit review object and
exactly one of them was made at that PR's final head**, since `.coderabbit.yaml` sets
`auto_incremental_review: false`. Those are **stale** reviews (exit 4), not refusals —
and 10 of them additionally carry a `Review skipped — Auto incremental reviews are
disabled` notice *inside a real review comment*, which is why refusal prose is outranked
by review evidence found in the same body.
