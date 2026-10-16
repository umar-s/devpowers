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
for p in "${WANT[@]}"; do
  claude plugin install "$p@$NAME" >/dev/null 2>&1 || die "claude: install $p@$NAME failed"
  codex plugin add "$p@$NAME" >/dev/null 2>&1 || die "codex: add $p@$NAME failed"
  claude plugin details "$p@$NAME" > "$W/claude.$p" 2>&1 || die "claude: details $p@$NAME failed"
done
(cd "$W/cwd" && codex debug prompt-input x </dev/null) > "$W/codex.prompt" 2>/dev/null \
  || die "codex: debug prompt-input failed"

# Reading the inventories and comparing, in one place: an inventory that cannot be read or does
# not have the expected shape is "could not run" (2) — never an empty list that passes or fails.
rc=0
python3 - "$EXPECTED" "$CATALOG/.claude-plugin/marketplace.json" "$W" "${WANT[@]}" <<'EOF' || rc=$?
import json, re, sys
try:
    expected_path, catalog_path, work, want = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
    expected, contract = {}, set()
    for line in open(expected_path, encoding="utf-8"):
        f = line.split()
        if not f or f[0].startswith("#"):
            continue
        if len(f) != 2 or f[1] not in ("both", "claude", "codex") or ":" not in f[0]:
            raise ValueError(f"bad contract line: {line.strip()!r}")
        plugin = f[0].split(":", 1)[0]
        contract.add(plugin)
        for h in ("claude", "codex"):
            expected.setdefault((plugin, h), set())
            if f[1] in ("both", h):
                expected[(plugin, h)].add(f[0])
    seen = {}
    for p in want:
        # "  Skills (3)  ci-gate, decompose, task" — the count guards against a shortened list
        m = re.search(r"^\s*Skills \((\d+)\)[ \t]*(.*)$", open(f"{work}/claude.{p}", encoding="utf-8").read(), re.M)
        if not m:
            raise ValueError(f"claude plugin details {p}: no 'Skills (N)' line")
        names = [s.strip() for s in m.group(2).split(",") if s.strip()]
        if len(names) != int(m.group(1)):
            raise ValueError(f"claude plugin details {p}: Skills ({m.group(1)}) lists {len(names)}")
        seen[(p, "claude")] = {f"{p}:{n}" for n in names}
    # A JSON list of messages; "### Available skills" occurs once in all of it, and every line
    # from there to "</skills_instructions>" is one "- <name>: <description>" entry — the shape
    # Codex 0.162.1 prints. Anything else in between is a shape this check does not know: 2.
    messages = json.load(open(f"{work}/codex.prompt", encoding="utf-8"))
    if not isinstance(messages, list):
        raise ValueError("codex debug prompt-input: not a JSON list")
    texts = [c["text"] for m in messages if isinstance(m, dict) and isinstance(m.get("content"), list)
             for c in m["content"] if isinstance(c, dict) and isinstance(c.get("text"), str)]
    heading, closing = "### Available skills\n", "\n</skills_instructions>"
    found = sum(t.count("### Available skills") for t in texts)
    if found != 1:
        raise ValueError(f"codex debug prompt-input: '### Available skills' occurs {found} times, expected 1")
    holders = [t for t in texts if heading in t]
    if not holders:
        raise ValueError("codex debug prompt-input: '### Available skills' is not a line of its own")
    after = "\n" + holders[0].split(heading, 1)[1]
    if closing not in after:
        raise ValueError("codex debug prompt-input: the skill list is not closed by </skills_instructions>")
    lines = after.split(closing, 1)[0].split("\n")[1:]
    entries = set()
    for line in lines:
        m = re.match(r"- (\S+?): \S", line)
        if not m:
            raise ValueError(f"codex debug prompt-input: unexpected line in the skill list {line[:80]!r}")
        entries.add(m.group(1))
    if not entries:
        raise ValueError("codex debug prompt-input: the skill list is empty")
    for p in want:
        seen[(p, "codex")] = {e for e in entries if e.startswith(p + ":")}
    plugins = [x["name"] for x in json.load(open(catalog_path, encoding="utf-8"))["plugins"]]
except Exception as e:
    print(f"check-skills: cannot read the inventories: {e}", file=sys.stderr)
    sys.exit(2)
rc = 0
for p in want:
    for h in ("claude", "codex"):
        exp, got = " ".join(sorted(expected[(p, h)])), " ".join(sorted(seen[(p, h)]))
        if exp == got:
            print(f"ok        {h:<6}  {p}  [{got or 'none'}]")
        else:
            print(f"MISMATCH  {h:<6}  {p}  expected [{exp or 'none'}]  got [{got or 'none'}]")
            rc = 1
unchecked = [x for x in plugins if x not in contract]
if unchecked:
    print("unchecked (not in the contract): " + " ".join(unchecked))
sys.exit(rc)
EOF
exit $rc
