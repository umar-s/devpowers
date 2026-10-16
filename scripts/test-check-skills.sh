#!/usr/bin/env bash
# test-check-skills.sh — offline controls for check-skills.sh: fake `claude` and `codex` (and a
# failing `git` where a case needs one) first on PATH, a fresh copy of the script and the catalog
# manifest per case. No network, no harness, no model:  bash scripts/test-check-skills.sh
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CATALOG=$(cd "$HERE/.." && pwd)
REAL_GIT=$(command -v git)
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0

# The fakes read their answers from $FAKE: claude.<plugin> ("a, b" — the `details` list),
# codex ("plugin:skill" per line — the prompt's skill entries), fail (one step to fail).
mkdir -p "$T/bin" "$T/badgit"
cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
fail=$(cat "$FAKE/fail" 2>/dev/null)
case "$1 $2" in
  "plugin marketplace") exit 0 ;;
  "plugin install") [ "$fail" = claude-install ] && exit 1; exit 0 ;;
  "plugin details") p=${3%@*}
    printf 'Fake (%s) 1.0.0\n\nComponent inventory\n  Skills (9)  %s\n  Agents (0)\n' \
      "$p" "$(cat "$FAKE/claude.$p" 2>/dev/null)"; exit 0 ;;
esac
exit 3
EOF
cat > "$T/bin/codex" <<'EOF'
#!/usr/bin/env bash
fail=$(cat "$FAKE/fail" 2>/dev/null)
case "$1 $2" in
  "plugin marketplace") exit 0 ;;
  "plugin add") [ "$fail" = codex-add ] && exit 1; exit 0 ;;
  "debug prompt-input") [ "$fail" = prompt-input ] && exit 1
    printf '[{"content":"## Skills'
    while read -r s; do [ -n "$s" ] && printf '\\n- %s: a skill (file: /c/SKILL.md)' "$s"; done < "$FAKE/codex"
    printf '"}]\n'; exit 0 ;;
esac
exit 3
EOF
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = init ] && exit 128; done\nexec %q "$@"\n' "$REAL_GIT" > "$T/badgit/git"
chmod +x "$T/bin/claude" "$T/bin/codex" "$T/badgit/git"

# A clone for --local: any committed tree will do, the fakes do not look inside.
"$REAL_GIT" init -q "$T/clone" && echo x > "$T/clone/f" && "$REAL_GIT" -C "$T/clone" add f \
  && "$REAL_GIT" -C "$T/clone" -c user.name=t -c user.email=t@t commit -qm t || exit 2

CONTRACT2='premortem:premortem both
md2pdf:md2pdf both'

# run <name> <expected rc> <contract|-none-> <claude.premortem> <claude.md2pdf> <codex lines> <fail> [args…]
run() {
  local name=$1 want=$2 contract=$3 cpm=$4 cmd=$5 cx=$6 fail=$7; shift 7
  local C=$T/case-$name
  mkdir -p "$C/scripts" "$C/.claude-plugin" "$C/fake" "$C/tmp"
  cp "$CATALOG/.claude-plugin/marketplace.json" "$C/.claude-plugin/"
  cp "$HERE/check-skills.sh" "$C/scripts/"
  [ "$contract" = -none- ] || printf '%s\n' "$contract" > "$C/scripts/expected-skills.txt"
  printf '%s' "$cpm" > "$C/fake/claude.premortem"
  printf '%s' "$cmd" > "$C/fake/claude.md2pdf"
  printf '%s\n' "$cx" > "$C/fake/codex"
  printf '%s' "$fail" > "$C/fake/fail"
  local path=$T/bin:$PATH tmp=$C/tmp
  [ "$fail" = git-init ] && path=$T/badgit:$path
  [ "$fail" = mktemp ] && tmp=$C/no-such-dir
  local out rc
  out=$(FAKE=$C/fake PATH=$path TMPDIR=$tmp bash "$C/scripts/check-skills.sh" "$@" 2>&1); rc=$?
  if [ "$rc" = "$want" ]; then
    echo "pass  $name (rc $rc)"
  else
    echo "FAIL  $name: rc $rc, expected $want"; sed 's/^/      /' <<<"$out"; fails=$((fails + 1))
  fi
}

both='premortem:premortem
md2pdf:md2pdf'
run match              0 "$CONTRACT2" premortem md2pdf "$both" ''           premortem md2pdf
run contract-default   0 "$CONTRACT2" premortem md2pdf "$both" ''
run local-clone        0 "$CONTRACT2" premortem md2pdf "$both" ''           --local premortem="$T/clone" premortem
run codex-missing      1 "$CONTRACT2" premortem md2pdf 'md2pdf:md2pdf' ''   premortem md2pdf
run claude-extra       1 "$CONTRACT2" premortem 'md2pdf, extra' "$both" ''  premortem md2pdf
run claude-only-ok     0 'premortem:premortem claude' premortem '' ''  ''   premortem
run claude-only-extra  1 'premortem:premortem claude' premortem '' 'premortem:premortem' '' premortem
run no-contract        2 -none-                  premortem md2pdf "$both" '' premortem
run empty-contract     2 '# comments only'       premortem md2pdf "$both" '' premortem
run no-contract-all    2 -none-                  premortem md2pdf "$both" ''
run empty-contract-all 2 '# comments only'       premortem md2pdf "$both" ''
run unknown-plugin     2 "$CONTRACT2" premortem md2pdf "$both" ''           nosuch
run local-not-git      2 "$CONTRACT2" premortem md2pdf "$both" ''           --local premortem="$T/bin" premortem
run local-not-catalog  2 "$CONTRACT2" premortem md2pdf "$both" ''           --local nosuch="$T/clone" premortem
run mktemp-fails       2 "$CONTRACT2" premortem md2pdf "$both" mktemp       premortem
run git-init-fails     2 "$CONTRACT2" premortem md2pdf "$both" git-init     premortem
run claude-install     2 "$CONTRACT2" premortem md2pdf "$both" claude-install premortem
run codex-add          2 "$CONTRACT2" premortem md2pdf "$both" codex-add    premortem
run prompt-input       2 "$CONTRACT2" premortem md2pdf "$both" prompt-input premortem

[ "$fails" -eq 0 ] && echo "all controls pass" || { echo "$fails control(s) failed"; exit 1; }
