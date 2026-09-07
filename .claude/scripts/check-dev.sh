#!/usr/bin/env bash
# DEV delivery check: is the pushed commit deployed, and is dev up?
#
#   bash .claude/scripts/check-dev.sh                    # latest runs on main + dev HTTP status
#   bash .claude/scripts/check-dev.sh --sha <sha>        # wait for that commit's runs to finish
#   bash .claude/scripts/check-dev.sh --sha <sha> --allow-no-runs
#                                                        # ... and accept "no runs" as legitimate
#
# --sha accepts any git revision (short sha, HEAD, tag): it is resolved to a full 40-char sha
# before querying, because `gh run list --commit` silently returns [] for an abbreviated one.
#
# With --sha, finding NO runs is a FAIL: absence of evidence is not evidence of success. Pass
# --allow-no-runs only when a change genuinely triggers nothing (it matched no path filter),
# and say so in the task file.
#
# Never touches prod. Read-only against GitHub and https://dev.nextgenmaher.com.
# Exit 0 if every run for the commit (or the latest runs) concluded success and dev returns
# HTTP 200; exit 1 otherwise.

set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
proj="${CLAUDE_PROJECT_DIR:-$(cd "$here/../.." && pwd)}"
ngm="${NGM_ROOT:-$HOME/git/ngm.app}"
[ -d "$proj/.git" ] && [ -f "$proj/app/package.json" ] && ngm="$proj"

repo="nagzstar/ngm.app"
dev_url="https://dev.nextgenmaher.com"
sha=""
allow_no_runs=0
while [ $# -gt 0 ]; do
  case "$1" in
    --sha) sha="${2:-}"; shift 2 ;;
    --allow-no-runs) allow_no_runs=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

# Count / filter helpers over the `gh run list` JSON.
jq_len()     { printf '%s' "$1" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{try{console.log(JSON.parse(d).length)}catch(e){console.log(0)}})'; }
jq_pending() { printf '%s' "$1" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{try{console.log(JSON.parse(d).filter(x=>x.status!=="completed").length)}catch(e){console.log(0)}})'; }

fail=0

if [ -n "$sha" ]; then
  # `gh run list --commit` matches the FULL sha only, and returns [] for an abbreviated one
  # with no error — which is why every short-sha caller silently saw "no runs found".
  full="$(git -C "$ngm" rev-parse --verify "${sha}^{commit}" 2>/dev/null)"
  if [ -z "$full" ]; then
    if printf '%s' "$sha" | grep -Eq '^[0-9a-f]{40}$'; then
      full="$sha"   # already full; just not resolvable in this checkout
    else
      echo "check-dev: cannot resolve '$sha' to a full sha in $ngm (gh needs the full 40-char sha)" >&2
      echo "CHECK-DEV FAIL"; exit 1
    fi
  fi
  [ "$full" != "$sha" ] && echo "check-dev: resolved $sha → $full"

  # Wait (bounded) for runs of this commit to appear and finish. Up to ~10 minutes.
  # CHECK_DEV_WAIT_ITERATIONS shortens the wait when testing the gate itself; leave it unset
  # for real delivery checks, where a run can genuinely take minutes to appear.
  iters="${CHECK_DEV_WAIT_ITERATIONS:-60}"
  runs="[]"; n=0; pending=0
  for _ in $(seq 1 "$iters"); do
    runs="$(gh run list -R "$repo" --commit "$full" --json databaseId,name,status,conclusion,url 2>/dev/null)"
    [ -z "$runs" ] && runs="[]"
    n="$(jq_len "$runs")"
    pending="$(jq_pending "$runs")"
    if [ "$n" -gt 0 ] && [ "$pending" -eq 0 ]; then break; fi
    sleep 10
  done

  if [ "$n" -eq 0 ]; then
    if [ "$allow_no_runs" -eq 1 ]; then
      echo "NOTE no workflow runs for $full — accepted because --allow-no-runs was passed"
    else
      echo "BAD  no workflow runs found for $full after waiting for them."
      echo "     Either the push matched no path filter (app/**, supabase/**, terraform/**, a workflow"
      echo "     file), or the runs never started. This is NOT a pass: re-run once the runs appear, or"
      echo "     pass --allow-no-runs if triggering nothing is genuinely correct for this change."
      fail=1
    fi
  elif [ "$pending" -gt 0 ]; then
    echo "BAD  $pending of $n run(s) for $full still not completed after the wait expired — not a pass."
    fail=1
  fi
else
  runs="$(gh run list -R "$repo" --branch main --limit 6 --json databaseId,name,status,conclusion,url,headSha 2>/dev/null)"
  [ -z "$runs" ] && runs="[]"
fi

printf '%s' "$runs" | node -e '
  let d=""; process.stdin.on("data",c=>d+=c); process.stdin.on("end",()=>{
    let r=[]; try { r=JSON.parse(d) } catch(e) {}
    let bad=0;
    for (const x of r) {
      const ok = x.status==="completed" && x.conclusion==="success";
      if (!ok) bad++;
      console.log(`${ok?"OK  ":"BAD "} ${x.name.padEnd(20)} ${x.status}/${x.conclusion||"-"} ${x.headSha?x.headSha.slice(0,7):""} ${x.url}`);
    }
    process.exit(bad?1:0);
  })' || fail=1

code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "$dev_url" 2>/dev/null || echo "000")"
if [ "$code" = "200" ]; then echo "OK   $dev_url → 200"; else echo "BAD  $dev_url → $code (free Supabase projects pause after inactivity — check that before debugging code)"; fail=1; fi

[ "$fail" -eq 0 ] && echo "CHECK-DEV PASS" || echo "CHECK-DEV FAIL"
exit "$fail"
