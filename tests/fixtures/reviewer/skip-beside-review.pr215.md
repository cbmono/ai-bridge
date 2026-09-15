<!-- This is an auto-generated comment: summarize by coderabbit.ai -->
<!-- review_stack_entry_start -->

<a href="https://app.coderabbit.ai/change-stack/cbmono/ai-bridge/pull/215#gh-light-mode-only"><img src="https://storage.googleapis.com/coderabbit_public_assets/review-stack-in-coderabbit-ui.svg" alt="Review Change Stack" width="202" height="32"></a><a href="https://app.coderabbit.ai/change-stack/cbmono/ai-bridge/pull/215#gh-dark-mode-only"><img src="https://storage.googleapis.com/coderabbit_public_assets/review-stack-in-coderabbit-ui-dark.svg" alt="Review Change Stack" width="202" height="32"></a>

<!-- review_stack_entry_end -->
<!-- This is an auto-generated comment: skip review by coderabbit.ai -->

> [!IMPORTANT]
> ## Review skipped
> 
> Auto reviews are disabled on this repository. Please check the settings in the CodeRabbit UI or the `.coderabbit.yaml` file in this repository. To trigger a single review, invoke the `@coderabbitai review` command.
> 
> <details>
> <summary>⚙️ Run configuration</summary>
> 
> **Configuration used**: Path: .coderabbit.yaml
> 
> **Review profile**: CHILL
> 
> **Plan**: Advanced
> 
> **Run ID**: `faa5c9f6-e5e5-4183-9aea-8a00a3eda70b`
> 
> </details>
> 
> You can disable this status message by setting the `reviews.review_status` to `false` in the CodeRabbit configuration file.
> 
> Use the checkbox below for a quick retry:
> - [ ] <!-- {"checkboxId":"e9bb8d72-00e8-4f67-9cb2-caf3b22574fe"} --> 🔍 Trigger review

<!-- end of auto-generated comment: skip review by coderabbit.ai -->

<!-- walkthrough_start -->

<details>
<summary>📝 Walkthrough</summary>

## Walkthrough

The project-manager tick workflow is split into on-demand step documents. Digest output selects applicable steps. New scripts fold answered questions and render awaiting queues. Tests cover the new scripts, step selection, document structure, and relocated guidance.

### Changes

**Tick workflow and derived queues**

|Layer / File(s)|Summary|
|---|---|
|**Answer folding and awaiting rendering** <br> `README.md`, `plugin/scripts/fold-answers.sh`, `plugin/scripts/build-awaiting.sh`, `tests/fold-answers.test.sh`, `tests/awaiting-render.test.sh`|Adds guarded YAML flow-list parsing, answer attribution, atomic folding, read-only listing, and atomic `AWAITING.md` rendering.|
|**Core prompt and digest step selection** <br> `plugin/agents/project-manager.md`, `plugin/scripts/tick-delta.sh`, `plugin/seed/.claude/settings.json`, `tests/tick-delta.test.sh`|Adds step-file loading rules, an ownership gate, cache configuration, and digest `steps:` output based on task status, answered questions, and terminal projects.|
|**On-demand tick step procedures** <br> `plugin/tick-steps/step-2-refine-drafts.md`, `plugin/tick-steps/step-3-dispatch.md`, `plugin/tick-steps/step-4-advance.md`, `plugin/tick-steps/step-5-reflect-merges.md`, `plugin/tick-steps/step-6-close-projects.md`, `plugin/tick-steps/step-7-knowledge-base.md`, `plugin/tick-steps/step-8-render.md`|Adds dedicated procedures for draft refinement, dispatch, advancement, merge reflection, project closure, knowledge-base work, and rendering.|
|**Workflow and integration validation** <br> `tests/*.test.sh`|Updates tests to inspect the new step documents and adds coverage for step selection, sentinels, ownership, queue rendering, and relocated procedure references.|

<!-- change_assessment_start -->
**Priority:** ➖ Normal









**Estimated code review effort:** 4 (Complex) | ~60 minutes

<!-- change_assessment_commit:"3e83817779c0cc00b0e7e8f7cc352bd120670444" -->
**Change:** Refactor
<!-- change_assessment_end -->

</details>

<!-- walkthrough_end -->
<!-- final_review_risk_start -->
**Merge Risk:** _🟡 Moderate_ · up to `3e838`
<!-- final_review_risk_coverage:{"sourceCommitId":"3e83817779c0cc00b0e7e8f7cc352bd120670444","coveredCommitId":"3e83817779c0cc00b0e7e8f7cc352bd120670444","kind":"reviewed"} -->

Task workflows can be blocked, repeated, or recorded with incorrect attribution, so these issues should be corrected before merge.
<!-- final_review_risk_end -->
<!-- pre_merge_checks_walkthrough_start -->

<details>
<summary>🚥 Pre-merge checks | ✅ 4 | ❌ 1</summary>

### ❌ Failed checks (1 warning)

|     Check name     | Status     | Explanation                                                                                                                                                                                               | Resolution                                                                         |
| :----------------: | :--------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------- |
| Docstring Coverage | ⚠️ Warning | Docstring coverage is 44.12% which is insufficient. The required threshold is 80.00%. Docstring coverage is scoped to functions touched by this diff. Analyzed 34 functions across 32 files. (2 skipped:… | Write docstrings for the functions missing them to satisfy the coverage threshold. |

<details>
<summary>✅ Passed checks (4 passed)</summary>

|         Check name         | Status   | Explanation                                                                                                                               |
| :------------------------: | :------- | :---------------------------------------------------------------------------------------------------------------------------------------- |
|     Linked Issues check    | ✅ Passed | Check skipped because no linked issues were found for this pull request.                                                                  |
| Out of Scope Changes check | ✅ Passed | Check skipped because no linked issues were found for this pull request.                                                                  |
|      Description Check     | ✅ Passed | Check skipped - CodeRabbit’s high-level summary is enabled.                                                                               |
|         Title check        | ✅ Passed | The title clearly and accurately summarizes the primary change: splitting the project-manager prompt into a core file and per-step files. |

</details>

<details>
<summary>Full details: Docstring Coverage</summary>

**Explanation**

Docstring coverage is 44.12% which is insufficient. The required threshold is 80.00%. Docstring coverage is scoped to functions touched by this diff. Analyzed 34 functions across 32 files. (2 skipped: 2 unsupported.)

</details>

</details>

<!-- pre_merge_checks_walkthrough_end -->
<!-- finishing_touch_checkbox_start -->

<details>
<summary>✨ Finishing Touches 💡 1</summary>

<!-- finishing_touch_suggestion:docstrings -->
<details>
<summary>📝 Generate docstrings 💡</summary>

- [ ] <!-- {"checkboxId":"7962f53c-55bc-4827-bfbf-6a18da830691"} --> Create stacked PR
- [ ] <!-- {"checkboxId":"3e1879ae-f29b-4d0d-8e06-d12b7ba33d98"} --> Commit on current branch

</details>
<details>
<summary>🧪 Generate unit tests (beta)</summary>

- [ ] <!-- {"checkboxId": "f47ac10b-58cc-4372-a567-0e02b2c3d479", "radioGroupId": "utg-output-choice-group-5657087344"} -->   Create PR with unit tests
- [ ] <!-- {"checkboxId": "6ba7b810-9dad-11d1-80b4-00c04fd430c8", "radioGroupId": "utg-output-choice-group-5657087344"} -->   Commit unit tests in branch `task-024-slim-the-project-manager-prompt`

</details>

</details>

<!-- finishing_touch_checkbox_end -->
<!-- tips_start -->

---

Thanks for using [CodeRabbit](https://coderabbit.ai?utm_source=oss&utm_medium=github&utm_campaign=cbmono/ai-bridge&utm_content=215)! It's free for OSS, and your support helps us grow. If you like it, consider giving us a shout-out.

<details>
<summary>❤️ Share</summary>

- [X](https://twitter.com/intent/tweet?text=I%20just%20used%20%40coderabbitai%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20the%20proprietary%20code.%20Check%20it%20out%3A&url=https%3A//coderabbit.ai)
- [Mastodon](https://mastodon.social/share?text=I%20just%20used%20%40coderabbitai%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20the%20proprietary%20code.%20Check%20it%20out%3A%20https%3A%2F%2Fcoderabbit.ai)
- [Reddit](https://www.reddit.com/submit?title=Great%20tool%20for%20code%20review%20-%20CodeRabbit&text=I%20just%20used%20CodeRabbit%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20proprietary%20code.%20Check%20it%20out%3A%20https%3A//coderabbit.ai)
- [LinkedIn](https://www.linkedin.com/sharing/share-offsite/?url=https%3A%2F%2Fcoderabbit.ai&mini=true&title=Great%20tool%20for%20code%20review%20-%20CodeRabbit&summary=I%20just%20used%20CodeRabbit%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20proprietary%20code)

</details>


<sub>Comment `@coderabbitai help` to get the list of available commands.</sub>

<!-- tips_end -->
