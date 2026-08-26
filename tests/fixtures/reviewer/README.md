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
