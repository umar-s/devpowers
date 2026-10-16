#!/usr/bin/env bash
# check-skills.sh — which skills each catalog plugin shows the model, in Claude Code and in Codex.
#
# Installs catalog plugins into throwaway homes of both harnesses (CLAUDE_CONFIG_DIR and
# CODEX_HOME under one mktemp directory — the user's own are never touched) and compares the
# skills each harness lists, without a model call, with scripts/expected-skills.txt:
#   Claude Code — `claude plugin details <plugin>@<catalog>` ("Skills (N)  a, b");
#   Codex       — `codex debug prompt-input`, the prompt the model would get ("- plugin:skill: …").
# The comparison is exact per plugin: a missing skill and an extra one both fail.
#
#   bash scripts/check-skills.sh                        # every plugin in the contract, as published
#   bash scripts/check-skills.sh premortem md2pdf       # only these
#   bash scripts/check-skills.sh --local premortem=~/Project/premortem premortem
#                                                       # that clone's committed HEAD, not GitHub
# Exit: 0 all match · 1 a mismatch · 2 the check could not run.
set -Eeuo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CATALOG=$(cd "$HERE/.." && pwd)
EXPECTED=$HERE/expected-skills.txt
die() { echo "check-skills: $*" >&2; exit 2; }
# Any step that fails outside an explicit check is "could not run" (2), never a mismatch (1):
# `set -e` alone would exit with the failed command's own code.
trap 'echo "check-skills: line $LINENO failed: $BASH_COMMAND" >&2; exit 2' ERR

declare -A LOCAL=()
WANT=()
while [ $# -gt 0 ]; do
  case $1 in
    --local) [ $# -ge 2 ] && [[ $2 == *=* ]] || die "--local needs <plugin>=<repo-dir>"
             LOCAL[${2%%=*}]=${2#*=}; shift 2 ;;
    -h|--help) awk 'NR > 1 && /^#/ {sub(/^# ?/, ""); print; next} NR > 1 {exit}' "$0"; exit 0 ;;
    -*) die "unknown option $1" ;;
    *) WANT+=("$1"); shift ;;
  esac
done
command -v claude >/dev/null || die "claude CLI not found"
command -v codex >/dev/null || die "codex CLI not found"

# The contract first, before anything is installed: unreadable or empty is "could not run".
# Plugins to check: the contract's, or the ones named — each must be in the contract.
[ -r "$EXPECTED" ] || die "no contract: $EXPECTED"
in_contract=$(awk '!/^#/ && NF {split($1, a, ":"); print a[1]}' "$EXPECTED" | sort -u)
[ -n "$in_contract" ] || die "$EXPECTED lists no skills"
mapfile -t CONTRACT <<<"$in_contract"
[ ${#WANT[@]} -gt 0 ] || WANT=("${CONTRACT[@]}")
for p in "${WANT[@]}"; do
  grep -qx -- "$p" <<<"$in_contract" || die "$p has no line in $EXPECTED"
done

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
export CLAUDE_CONFIG_DIR=$W/claude CODEX_HOME=$W/codex
mkdir -p "$CLAUDE_CONFIG_DIR" "$CODEX_HOME" "$W/market/.claude-plugin" "$W/cwd"

# The catalog as published, except --local entries: those point at a `git archive HEAD` of the
# clone (what a release would ship), at the entry's own subdirectory.
for p in "${!LOCAL[@]}"; do
  git -C "${LOCAL[$p]}" rev-parse --git-dir >/dev/null 2>&1 || die "--local $p: ${LOCAL[$p]} is not a git clone"
  mkdir -p "$W/market/local/$p"
  git -C "${LOCAL[$p]}" archive HEAD | tar -x -C "$W/market/local/$p"
done
NAME=$(python3 - "$CATALOG/.claude-plugin/marketplace.json" "$W/market/.claude-plugin/marketplace.json" "${!LOCAL[@]}" <<'EOF'
import json, sys
src, dst, local = sys.argv[1], sys.argv[2], set(sys.argv[3:])
cat = json.load(open(src))
names = {p["name"] for p in cat["plugins"]}
for p in local - names:
    sys.exit(f"check-skills: --local {p}: no such plugin in the catalog")
for p in cat["plugins"]:
    if p["name"] in local:
        sub = p["source"].get("path", ".") if isinstance(p["source"], dict) else "."
        p["source"] = "./" + "/".join(x for x in ("local", p["name"], sub) if x != ".")
json.dump(cat, open(dst, "w"), indent=2)
print(cat["name"])
EOF
) || exit 2
git -C "$W/market" init -q
git -C "$W/market" add -A
git -C "$W/market" -c user.name=check -c user.email=check@localhost commit -qm check

claude plugin marketplace add "$W/market" >/dev/null 2>&1 || die "claude: marketplace add failed"
codex plugin marketplace add "$W/market" >/dev/null 2>&1 || die "codex: marketplace add failed"
: > "$W/claude.seen"
for p in "${WANT[@]}"; do
  claude plugin install "$p@$NAME" >/dev/null 2>&1 || die "claude: install $p@$NAME failed"
  codex plugin add "$p@$NAME" >/dev/null 2>&1 || die "codex: add $p@$NAME failed"
  details=$(claude plugin details "$p@$NAME" 2>&1) || die "claude: details $p@$NAME failed"
  sed -n 's/^ *Skills ([0-9]*) *//p' <<<"$details" | tr ',' '\n' \
    | awk -v p="$p" 'NF {gsub(/ /, ""); print p ":" $0}' >> "$W/claude.seen"
done
prompt=$(cd "$W/cwd" && codex debug prompt-input x </dev/null 2>/dev/null) || die "codex: debug prompt-input failed"
grep -oE '\\n- [A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+: ' <<<"$prompt" \
  | sed -E 's/^\\n- //; s/: $//' > "$W/codex.seen" || true

rc=0
for p in "${WANT[@]}"; do
  for h in claude codex; do
    want=$(awk -v p="$p" -v h="$h" '!/^#/ && NF && index($1, p ":") == 1 && ($2 == "both" || $2 == h) {print $1}' "$EXPECTED" | sort -u | paste -sd' ')
    got=$(grep -E "^$p:" "$W/$h.seen" | sort -u | paste -sd' ' || true)
    if [ "$want" = "$got" ]; then
      echo "ok        $h  $p  [${got:-none}]"
    else
      echo "MISMATCH  $h  $p  expected [${want:-none}]  got [${got:-none}]"; rc=1
    fi
  done
done
unchecked=$(python3 -c 'import json,sys; print(" ".join(p["name"] for p in json.load(open(sys.argv[1]))["plugins"]))' \
  "$CATALOG/.claude-plugin/marketplace.json" | tr ' ' '\n' | grep -vxF -f <(printf '%s\n' "${CONTRACT[@]}") | paste -sd' ' || true)
[ -z "$unchecked" ] || echo "unchecked (not in the contract): $unchecked"
exit $rc
