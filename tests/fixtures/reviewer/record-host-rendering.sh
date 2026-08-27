#!/usr/bin/env bash
#
# record-host-rendering.sh — re-record `host-rendering.txt`, the ORACLE the block reader in
# `symlink/scripts/review-clearance.sh` is measured against.
#
# WHY AN ORACLE AND NOT ANOTHER PROPERTY. That reader answers "which lines of this comment
# does GitHub put on the page as MARKUP", and for five rounds it was checked against
# properties of ITSELF — most recently that one of its two readings is a subset of the
# other, which an intersection and a union satisfy BY CONSTRUCTION and which therefore
# survived every destructive mutant applied to it. A test that cannot go red is not a test.
# The only thing that can contradict this reader is the renderer it is modelling, so that
# is what it is now compared against: each case below is sent to github.com's own Markdown
# endpoint and the answer is written down.
#
# RECORDED, NOT CALLED. The suite must run offline and must not depend on a live host, so
# the answers are checked in and this script exists to refresh them. Re-run it when a case
# is added, or to confirm the host still answers the same way:
#
#   tests/fixtures/reviewer/record-host-rendering.sh          # rewrite the fixture
#   tests/fixtures/reviewer/record-host-rendering.sh --check   # 0 if it is still current
#
# It needs `gh` authenticated against github.com and it makes one API call per case.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/host-rendering.txt"
MARKER='<!-- walkthrough_start -->'
REFUSAL='Review limit reached'
HEAD_SHA='88c106a8dd2b9ae14e001918022d4909e5357460'

command -v gh >/dev/null 2>&1 || { echo "gh is required to record the oracle" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required to record the oracle" >&2; exit 2; }
command -v perl >/dev/null 2>&1 || { echo "perl is required to classify" >&2; exit 2; }

# --- the cases ---------------------------------------------------------------
# `%P%` is the probe: the refusal phrase in the `refusal` family, the vendor's own review
# marker in the `marker` family. Each case is a CONSTRUCT the reader has to get right, and
# the list is the record of what has been asked — including the shapes that were once
# answered wrongly, so a regression is a re-record away from being visible.
cases() {
  cat <<'CASES'
plain-text                  |%P%
fence-top-level             |```\n%P%\n```
fence-three-space           |   ```\n   %P%\n   ```
fence-four-space-literal    |    ```\n%P%\n    ```
fence-tab-literal           | \t```\n%P%\n \t```
fence-closer-shorter        |````\n%P%\n```
fence-closer-info-string    |```\n%P%\n```js
fence-backtick-in-info      |```a`b\n%P%\n```
fence-tilde-vs-backtick     |~~~\n%P%\n```
fence-unbalanced            |```\n%P%
fence-crlf                  |```\r\n%P%\r\n```
fence-crlf-after-close      |```\r\nx\r\n```\r\n%P%
quote-plain                 |> %P%
quote-fence                 |> ```\n> %P%\n> ```
quote-fence-unquoted-body   |> ```\n%P%\n> ```
quote-depth-2-fence         |> > ```\n> %P%\n> > ```
list-sibling-markers        |- ```\n- %P%\n- ```
list-sibling-star           |* ```\n* %P%\n* ```
list-sibling-ordered        |1. ```\n2. %P%\n3. ```
list-sibling-ordered-wide   |10. ```\n11. %P%\n12. ```
list-sibling-tab            |-\t```\n-\t%P%\n-\t```
list-indented-marker        |  - ```\n  - %P%\n  - ```
list-continuation           |- ```\n  %P%\n  ```
list-dedent-ends-item       |- ```\n  code\n%P%
list-sibling-ends-fence     |- ```\n  code\n- %P%
list-nested-deeper          |- ```\n  - %P%\n  ```
list-closes-top-fence       |```\n%P%\n- ```
html-details                |<details>\n```\n%P%\n```\n</details>
html-pre                    |<pre>\n%P%\n</pre>
html-blank-line-ends        |<details>\n\n```\n%P%\n```
html-unknown-tag            |<okf-widget>\n```\n%P%\n```
html-closing-tag            |</okf-widget>\n```\n%P%\n```
html-in-quote-then-fence    |> <details>\n\n```\n%P%\n```
html-in-quote-list-fence    |> <details>\n- ```\n- %P%\n- ```
html-in-list-sibling-fence  |- <details>\n- ```\n- %P%\n- ```
html-in-quote-then-list     |> <details>\n\n- ```\n- %P%\n- ```
html-in-quote-quoted-fence  |> <details>\n> ```\n> %P%\n> ```
html-in-quote-top-fence     |> <details>\n```\n%P%\n```
html-type1-pre-blank        |<pre>\n\n%P%\n</pre>
html-inline-then-fence      |<span>hello\n```\n%P%\n```
list-item-relative-indent   |-   item\n\n    ```\n    %P%\n    ```
span-uneven-runs            |``a`b\n%P%\nc``
span-open-then-probe        |`open\n%P%
quote-indented-code         |>     %P%
list-loose-blank-then-item  |- ```\n\n- %P%\n- ```
list-blank-inside-item      |- ```\n\n  %P%\n  ```
html-in-list-then-fence     |- <details>\n- ```\n  %P%\n  ```
fence-in-quote-then-dedent  |> ```\n> code\n\n%P%
setext-then-fence           |title\n===\n```\n%P%\n```
indented-code               |    %P%
code-span-inline            |`%P%`
code-span-multiline         |`start\n%P%\nend`
html-comment-wraps          |<!--\n%P%\n-->
table-cell                  |\| a \|\n\| - \|\n\| %P% \|
CASES
}

# The CONTENT family asks a different question of the same renderer: does this body put
# ANY readable character on the page? It is what `renders_content` is measured against —
# the test that decides whether a review object at the head carries a claim or is one of
# the empty `COMMENTED` objects the host mints for a thread reply. Every row here is a
# construct that renders to nothing while carrying bytes, or a control that carries a
# glyph and must not be mistaken for one that does not. `%P%` is not substituted.
content_cases() {
  cat <<'CASES'
c-empty-comment             |<!-- -->
c-comment-with-text         |<!--x-->
c-comment-multiline         |<!--\nhidden\n-->
c-zero-width-space          |\342\200\213
c-lrm                       |\342\200\216
c-rlm                       |\342\200\217
c-non-breaking-space        |\302\240
c-function-application      |\342\201\241
c-invisible-plus            |\342\201\244
c-interlinear-anchor        |\357\277\271
c-rlo                       |\342\200\256
c-invisible-times           |\342\201\242
c-mongolian-vowel-sep       |\341\240\216
c-variation-selector        |\357\270\200
c-emoji-variation-selector  |\357\270\217
c-hangul-choseong-filler    |\341\205\237
c-hangul-filler             |\343\205\244
c-combining-grapheme-joiner |\315\217
c-numeric-char-ref          |&#8203;
c-named-char-ref            |&zwnj;
c-empty-element             |<div></div>
c-thematic-break            |---
c-link-ref-def-degenerate   |[//]: # ()
c-link-ref-def-with-text    |[//]: # (a markdown comment)
c-link-ref-def-plain        |[x]: /y
c-link-ref-def-opens-html   |[a]: /b <!--\nhidden\n-->\nreviewed
c-link-ref-def-swallows-open|   [a]: /b<!--\nlgtm\n-->
c-empty-link                |[](url)
c-tag-with-gt-in-attribute  |<a href="1>2"></a>
c-tag-with-gt-in-title      |<div title="a>b"></div>
c-doctype                   |<!DOCTYPE html>
c-cdata                     |<![CDATA[x]]>
c-cdata-with-gt             |<![CDATA[a > b]]>
c-comment-with-gt           |<!-- a > b -->
c-reference-link-empty      |[][r]\n\n[r]: /x
c-processing-instruction    |<?php ?>
c-html-declaration          |<!ENTITY x "y">
c-image-no-alt              |![](/x.png)
c-autolink-only             |<https://example.com/a>
c-control-glyph-word        |ok
c-control-word-after-hidden |<!-- x -->\342\200\213ok
c-control-word-in-element   |<div>lgtm</div>
c-control-hidden-in-word    |no&#8203;1
c-control-link-with-text    |[see this](url)
c-image-alt-is-not-a-glyph  |![a diagram](/x.png)
c-control-doctype-then-word |<!DOCTYPE html>\nreviewed
CASES
}

# --- classification ----------------------------------------------------------
# A probe is VISIBLE when a reader looking at the rendered page sees those characters —
# whether as prose or as a quotation inside a code block, which is the same thing to a
# human and the opposite thing to a naive matcher. It is HIDDEN only when the host emits
# it inside an HTML comment, i.e. as markup nobody can read.
#
# The refusal family asks a second question, because "in a code block" is not the same
# answer there: a quoted refusal is deliberately read as a DISCUSSION of one. So it
# records three values and only `prose` is asserted on.
classify() { # <family> — reads the rendered HTML on stdin
  OKF_FAMILY="$1" perl -0777 -ne '
    my $family = $ENV{OKF_FAMILY}; my $raw = $_;
    my $nocomment = $raw; $nocomment =~ s{<!--.*?-->}{}gs;
    my $prose = $nocomment;
    $prose =~ s{<pre>.*?</pre>}{}gs; $prose =~ s{<code[^>]*>.*?</code>}{}gs;
    if ($family eq "content") {
      # What a reader SEES: everything that is an instruction to the renderer rather
      # than a glyph comes out first — the six raw-HTML productions and the character
      # references — and the question is whether an ASCII alphanumeric is left.
      my $t = $nocomment;
      $t =~ s{<!\[CDATA\[.*?\]\]>}{}gs; $t =~ s{<\?.*?\?>}{}gs;
      $t =~ s{<![^>]*>}{}gs;              $t =~ s{<[^>]*>}{}gs;
      $t =~ s{&#?[0-9A-Za-z]+;}{}g;
      print $t =~ /[0-9A-Za-z]/ ? "glyph" : "blank";
    } elsif ($family eq "marker") {
      print $nocomment =~ /walkthrough_start/ ? "visible" : "hidden";
    } else {
      print $prose     =~ /Review limit reached/ ? "prose"
          : $nocomment =~ /Review limit reached/ ? "quoted" : "hidden";
    }'
}

ask() { # <family> <body-file> — the host's verdict for one case, or empty on API failure
  jq -Rs '{text: ., mode: "markdown"}' < "$2" > "$TMPD/req.json"
  # PRINTS NOTHING ON A FAILED OR EMPTY RESPONSE, on purpose: `classify` reads whatever
  # lands on its stdin and always answers SOMETHING that looks like a verdict — an empty
  # body reads as "hidden" (refusal/marker) or "blank" (content), which is a real answer
  # for a REAL empty page and indistinguishable from one for an API call that never
  # rendered anything at all. So the raw response is validated HERE, before classify ever
  # sees it, and on every single call — not just checked in aggregate at the end — because
  # a subset of calls failing this way is the dangerous case: it would silently record a
  # refusal or marker case as the SAFE verdict instead of erroring, which is exactly the
  # direction nothing else in this script would notice. `raw` merges stdout and stderr so
  # gh's own error text is captured for the diagnostic, never fed to `classify`.
  local raw rc
  raw="$(gh api -X POST /markdown --input "$TMPD/req.json" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "ask: gh api /markdown failed for $1 (exit $rc): ${raw:-<no output>}" >&2
    return 1
  fi
  if [ -z "$raw" ]; then
    echo "ask: gh api /markdown returned an EMPTY response for $1 — refusing to classify a body the host was never actually asked about" >&2
    return 1
  fi
  printf '%s' "$raw" | classify "$1"
}

TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT

{
  cat <<'HDR'
# host-rendering.txt — HOW GITHUB ITSELF RENDERS EACH OF THESE BODIES.
#
# Recorded from github.com's Markdown endpoint by `record-host-rendering.sh`, which is
# checked in beside this file; re-run it to refresh or to verify. Every line below is the
# HOST's answer, not this repository's — it is the only thing that can prove the block
# reader in `symlink/scripts/review-clearance.sh` wrong, and `review-clearance.test.sh`
# asserts against it.
#
# Format, one case per block:
#
#   @@@ <family> <verdict> <name>
#   <body, verbatim, byte for byte as the host was asked about it>
#   @@@ end
#
#   family  refusal  the body carries the human-visible refusal heading
#           marker   the body carries the head SHA and the vendor's own review marker
#   verdict prose    (refusal) the host puts the refusal on the page as READABLE PROSE.
#                    The gate MUST report a refusal for these: this is the direction that
#                    merges an unreviewed PR, and it is asserted.
#           quoted   (refusal) the host puts it inside a code block. A quoted refusal is
#                    deliberately read as a DISCUSSION of one, so nothing is asserted —
#                    but the count is, so the battery cannot pass by refusing everything.
#           hidden   (refusal) not on the page at all.
#           visible  (marker) the reader SEES the marker's characters, so it is somebody's
#                    quotation and not the vendor's machine claim. Must NOT clear.
#           hidden   (marker) emitted inside an HTML comment: the vendor's own marker.
#           blank    (content) the page shows no ASCII alphanumeric at all. A review
#                    object with such a body is NOT a claim, and the gate must not clear
#                    on it — asserted.
#           glyph    (content) the page shows a character. May still be read as blank
#                    (the safe direction), so only the COUNT that clear is asserted.
HDR
  printf '#\n# Recorded %s against %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "github.com/api/markdown"
  while IFS='|' read -r name tmpl; do
    name="${name%"${name##*[![:space:]]}"}"
    [ -n "$name" ] || continue
    for family in refusal marker; do
      if [ "$family" = refusal ]; then probe="$REFUSAL"; else probe="$MARKER"; fi
      body="${tmpl//%P%/$probe}"
      # The marker family needs the head named somewhere, or route C has no pin and the
      # case would answer "did not clear" for a reason that is not the one being measured.
      [ "$family" = marker ] && body="$HEAD_SHA\n\n$body"
      # Sent to the host with the trailing newline it is stored with, so the bytes the
      # host answered about are exactly the bytes the suite replays.
      printf '%b\n' "$body" > "$TMPD/body"
      verdict="$(ask "$family" "$TMPD/body")"
      [ -n "$verdict" ] || { echo "could not classify $family/$name" >&2; exit 2; }
      printf '@@@ %s %s %s\n' "$family" "$verdict" "$name"
      cat "$TMPD/body"; printf '@@@ end\n'
    done
  done < <(cases)
  while IFS='|' read -r name tmpl; do
    name="${name%"${name##*[![:space:]]}"}"
    [ -n "$name" ] || continue
    printf '%b\n' "$tmpl" > "$TMPD/body"
    verdict="$(ask content "$TMPD/body")"
    [ -n "$verdict" ] || { echo "could not classify content/$name" >&2; exit 2; }
    printf '@@@ content %s %s\n' "$verdict" "$name"
    cat "$TMPD/body"; printf '@@@ end\n'
  done < <(content_cases)
} > "$TMPD/out"

if [ "${1:-}" = "--check" ]; then
  # The recorded date line is expected to differ; everything else must not.
  if diff <(grep -v '^# Recorded ' "$OUT") <(grep -v '^# Recorded ' "$TMPD/out") >/dev/null; then
    echo "host-rendering.txt is current"; exit 0
  fi
  echo "host-rendering.txt is STALE — the host answers differently now:" >&2
  diff <(grep -v '^# Recorded ' "$OUT") <(grep -v '^# Recorded ' "$TMPD/out") >&2
  exit 1
fi
mv "$TMPD/out" "$OUT"
echo "recorded $(grep -c '^@@@ end' "$OUT") cases into $OUT"
