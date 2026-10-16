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
# codex ("plugin:skill" per line — the prompt's skill entries), fail (one step to fail or
# garble). The fake claude keeps a copy of the marketplace it was given, in $FAKE/market.
mkdir -p "$T/bin" "$T/badgit"
cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
fail=$(cat "$FAKE/fail" 2>/dev/null)
case "$1 $2" in
  "plugin marketplace") cp -r "$4" "$FAKE/market"; exit 0 ;;
  "plugin install") [ "$fail" = claude-install ] && exit 1; exit 0 ;;
  "plugin details") p=${3%@*}; list=$(cat "$FAKE/claude.$p" 2>/dev/null)
    n=$(tr ',' '\n' <<<"$list" | grep -c '[^ ]')
    [ "$fail" = details-count ] && n=$((n + 1))
    [ "$fail" = details-garbled ] && { echo "Fake ($p) 1.0.0"; exit 0; }
    printf 'Fake (%s) 1.0.0\n\nComponent inventory\n  Skills (%s)  %s\n  Agents (0)\n' "$p" "$n" "$list"
    exit 0 ;;
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
    # the shape Codex 0.162.1 prints: messages, one text with the skills block; the entry lines
    # come from $FAKE/codex. Garbled variants for the controls that must exit 2.
    exec python3 - "$FAKE/codex" "$fail" <<'PY'
import json, sys
skills = [s.strip() for s in open(sys.argv[1]) if s.strip()]
fail = sys.argv[2]
block = "\n".join(["## Skills", "A skill is…", "### Available skills", "- imagegen: not a plugin skill"]
                  + [f"- {s}: a skill (file: /c/SKILL.md)" for s in skills] + ["</skills_instructions>"])
msgs = [{"type": "message", "role": "developer", "content": [{"type": "input_text", "text": block}]},
        {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "x"}]}]
if fail == "prompt-no-skills":
    msgs = msgs[1:]
if fail == "prompt-not-json":
    print("BROKEN ## Skills\\n- premortem:premortem: text"); sys.exit(0)
if fail == "prompt-two-blocks":
    msgs.append(msgs[0])
if fail == "prompt-entry-outside":   # the entries sit in another message, the block is empty
    msgs[0]["content"][0]["text"] = "## Skills\n### Available skills\n</skills_instructions>"
    msgs[1]["content"][0]["text"] = "\n".join(f"- {s}: a skill" for s in skills)
if fail == "prompt-bad-entry":
    msgs[0]["content"][0]["text"] = block.replace("</skills_instructions>", "- no-description\n</skills_instructions>")
print(json.dumps(msgs))
PY
    ;;
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
run details-garbled    2 "$CONTRACT2" premortem md2pdf "$both" details-garbled premortem
run details-count      2 "$CONTRACT2" premortem md2pdf "$both" details-count premortem
run prompt-no-skills   2 "$CONTRACT2" premortem md2pdf "$both" prompt-no-skills premortem
run prompt-not-json    2 "$CONTRACT2" premortem md2pdf "$both" prompt-not-json premortem
run prompt-not-json-claude-only 2 'premortem:premortem claude' premortem '' '' prompt-not-json premortem
run prompt-two-blocks  2 "$CONTRACT2" premortem md2pdf "$both" prompt-two-blocks premortem
run prompt-entry-outside 2 "$CONTRACT2" premortem md2pdf "$both" prompt-entry-outside premortem
run prompt-bad-entry   2 "$CONTRACT2" premortem md2pdf "$both" prompt-bad-entry premortem
run bad-contract-line  2 'premortem:premortem everywhere' premortem md2pdf "$both" '' premortem

# --local takes the clone's committed HEAD, at the entry's own subdirectory, and leaves the other
# entries as published: a `url` entry (premortem, the repo root) and a `git-subdir` one (co-rar,
# plugins/co-rar), each clone with an uncommitted edit and an untracked file that must not ship.
mkclone() {  # <dir> <subdir>
  "$REAL_GIT" init -q "$1" && mkdir -p "$1/$2" && echo committed > "$1/$2/marker" \
    && "$REAL_GIT" -C "$1" add -A && "$REAL_GIT" -C "$1" -c user.name=t -c user.email=t@t commit -qm t \
    && echo dirty > "$1/$2/marker" && echo untracked > "$1/$2/untracked"
}
L=$T/case-local-content
mkdir -p "$L/scripts" "$L/.claude-plugin" "$L/fake" "$L/tmp"
cp "$CATALOG/.claude-plugin/marketplace.json" "$L/.claude-plugin/"
cp "$HERE/check-skills.sh" "$L/scripts/"
printf 'premortem:premortem both\nco-rar:co-rar both\n' > "$L/scripts/expected-skills.txt"
printf premortem > "$L/fake/claude.premortem"; printf co-rar > "$L/fake/claude.co-rar"
printf 'premortem:premortem\nco-rar:co-rar\n' > "$L/fake/codex"; : > "$L/fake/fail"
if mkclone "$T/pm" . && mkclone "$T/cr" plugins/co-rar \
   && FAKE=$L/fake PATH=$T/bin:$PATH TMPDIR=$L/tmp bash "$L/scripts/check-skills.sh" \
        --local premortem="$T/pm" --local co-rar="$T/cr" premortem co-rar >/dev/null 2>&1 \
   && python3 - "$CATALOG/.claude-plugin/marketplace.json" "$L/fake/market" <<'EOF'
import json, pathlib, sys
pub = {p["name"]: p for p in json.load(open(sys.argv[1]))["plugins"]}
m = pathlib.Path(sys.argv[2])
got = {p["name"]: p for p in json.load(open(m / ".claude-plugin/marketplace.json"))["plugins"]}
assert got["premortem"]["source"] == "./local/premortem", got["premortem"]["source"]
assert got["co-rar"]["source"] == "./local/co-rar/plugins/co-rar", got["co-rar"]["source"]
for name in pub:
    if name not in ("premortem", "co-rar"):
        assert got[name] == pub[name], name
for path in ("local/premortem/marker", "local/co-rar/plugins/co-rar/marker"):
    assert (m / path).read_text() == "committed\n", path
    assert not (m / path).with_name("untracked").exists(), path
EOF
then echo "pass  local-content (HEAD, subdirectory, neighbours untouched)"
else echo "FAIL  local-content"; fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && echo "all controls pass" || { echo "$fails control(s) failed"; exit 1; }
