#!/usr/bin/env bash
# check-skills.sh — which skills each catalog plugin shows the model, in Claude Code and in Codex.
#
# Installs catalog plugins into throwaway homes of both harnesses (CLAUDE_CONFIG_DIR and
# CODEX_HOME under one mktemp directory — the user's own are never touched) and compares the
# skills each harness lists, without a model call, with scripts/expected-skills.txt:
#   Claude Code — `claude plugin details <plugin>@<catalog>` ("Skills (N)  a, b");
#   Codex       — `codex debug prompt-input`, the prompt the model would get ("- plugin:skill: …").
# The comparison is exact per plugin: a missing skill and an extra one both fail. A plugin the
# contract marks `not-in-codex` must be refused by `codex plugin add` — the catalog entry's
# `"policy": {"installation": "NOT_AVAILABLE"}`; an install that succeeds is a mismatch.
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

# Plugin names end up in paths under the work directory: one plain component, nothing else.
NAME_RE='^[A-Za-z0-9][A-Za-z0-9._-]*$'
declare -A LOCAL=()
WANT=()
while [ $# -gt 0 ]; do
  case $1 in
    --local) [ $# -ge 2 ] && [[ $2 == *=* ]] || die "--local needs <plugin>=<repo-dir>"
             name=${2%%=*}
             [[ $name =~ $NAME_RE ]] || die "--local: '$name' is not a plugin name"
             LOCAL[$name]=${2#*=}; shift 2 ;;
    -h|--help) awk 'NR > 1 && /^#/ {sub(/^# ?/, ""); print; next} NR > 1 {exit}' "$0"; exit 0 ;;
    -*) die "unknown option $1" ;;
    *) [[ $1 =~ $NAME_RE ]] || die "'$1' is not a plugin name"
       WANT+=("$1"); shift ;;
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
  [[ $p =~ $NAME_RE ]] || die "$EXPECTED: '$p' is not a plugin name"
  grep -Fqx -- "$p" <<<"$in_contract" || die "$p has no line in $EXPECTED"
done
# Plugins Codex must refuse; the contract as a whole is validated with the comparison below.
not_in_codex=$(awk '!/^#/ && NF == 2 && $1 !~ /:/ && $2 == "not-in-codex" {print $1}' "$EXPECTED")
# --local entries: in the catalog and a git clone, checked before anything is written.
in_catalog=$(python3 -c 'import json, sys; print("\n".join(p["name"] for p in json.load(open(sys.argv[1]))["plugins"]))' \
  "$CATALOG/.claude-plugin/marketplace.json")
for p in "${!LOCAL[@]}"; do
  grep -Fqx -- "$p" <<<"$in_catalog" || die "--local $p: no such plugin in the catalog"
  git -C "${LOCAL[$p]}" rev-parse --git-dir >/dev/null 2>&1 || die "--local $p: ${LOCAL[$p]} is not a git clone"
done

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
export CLAUDE_CONFIG_DIR=$W/claude CODEX_HOME=$W/codex
mkdir -p "$CLAUDE_CONFIG_DIR" "$CODEX_HOME" "$W/market/.claude-plugin" "$W/cwd"

# The catalog as published, except --local entries: those point at a `git archive HEAD` of the
# clone (what a release would ship), at the entry's own subdirectory.
for p in "${!LOCAL[@]}"; do
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
  if ! grep -Fqx -- "$p" <<<"$not_in_codex"; then
    codex plugin add "$p@$NAME" >/dev/null 2>&1 || die "codex: add $p@$NAME failed"
  # Refused by the policy is the expected outcome, installed is a mismatch; any other failure
  # says nothing about the policy: 2.
  elif codex plugin add "$p@$NAME" > "$W/codex-add.$p" 2>&1; then
    echo installed > "$W/codex.$p"
  elif grep -Fq "plugin \`$p\` is not available for install" "$W/codex-add.$p"; then
    echo refused > "$W/codex.$p"
  else
    die "codex: add $p@$NAME failed, and not as refused by policy"
  fi
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
    expected, contract, not_in_codex = {}, set(), set()
    for line in open(expected_path, encoding="utf-8"):
        f = line.split()
        if not f or f[0].startswith("#"):
            continue
        if len(f) == 2 and f[1] == "not-in-codex" and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", f[0]):
            plugin = f[0]
            not_in_codex.add(plugin)
        elif len(f) == 2 and f[1] in ("both", "claude", "codex") and ":" in f[0]:
            plugin = f[0].split(":", 1)[0]
        else:
            raise ValueError(f"bad contract line: {line.strip()!r}")
        contract.add(plugin)
        for h in ("claude", "codex"):
            expected.setdefault((plugin, h), set())
            if f[1] in ("both", h):
                expected[(plugin, h)].add(f[0])
    for p in not_in_codex:
        if expected[(p, "codex")]:
            raise ValueError(f"bad contract: {p} is not-in-codex and lists skills for Codex")
    # not-in-codex plugins: what `codex plugin add` did — refused by the policy, or installed
    refused = {}
    for p in want:
        if p in not_in_codex:
            status = open(f"{work}/codex.{p}", encoding="utf-8").read().strip()
            if status not in ("refused", "installed"):
                raise ValueError(f"codex plugin add {p}: unknown outcome {status!r}")
            refused[p] = status == "refused"
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
    heading, closing = "### Available skills", "</skills_instructions>"
    found = sum(t.count(heading) for t in texts)
    if found != 1:
        raise ValueError(f"codex debug prompt-input: '{heading}' occurs {found} times, expected 1")
    lines = next(t for t in texts if heading in t).split("\n")
    start = next(i for i, l in enumerate(lines) if heading in l)
    if lines[start] != heading:
        raise ValueError(f"codex debug prompt-input: '{heading}' is not a line of its own: {lines[start][:80]!r}")
    if closing not in lines[start + 1:]:
        raise ValueError(f"codex debug prompt-input: the skill list is not closed by a '{closing}' line")
    end = lines.index(closing, start + 1)
    entries = set()
    for line in lines[start + 1:end]:
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
        if h == "codex" and p in not_in_codex:
            exp, skills = "not installable", got
            got = exp if refused[p] and not skills else \
                ("refused" if refused[p] else "installed") + f", skills: {skills or 'none'}"
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
