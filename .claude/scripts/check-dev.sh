#!/usr/bin/env bash
# DEV delivery check: is the pushed commit deployed, and is dev up?
#
#   bash .claude/scripts/check-dev.sh                # latest runs on main + dev HTTP status
#   bash .claude/scripts/check-dev.sh --sha <sha>    # wait for that commit's runs to finish
#
# Never touches prod. Read-only against GitHub and https://dev.nextgenmaher.com.
# Exit 0 if every run for the commit (or the latest runs) concluded success and dev returns
# HTTP 200; exit 1 otherwise.

set -u
repo="nagzstar/ngm.app"
dev_url="https://dev.nextgenmaher.com"
sha=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sha) sha="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

fail=0

if [ -n "$sha" ]; then
  # Wait (bounded) for runs of this commit to appear and finish. Up to ~10 minutes.
  for _ in $(seq 1 60); do
    runs="$(gh run list -R "$repo" --commit "$sha" --json databaseId,name,status,conclusion,url 2>/dev/null)"
    n="$(printf '%s' "$runs" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{try{console.log(JSON.parse(d).length)}catch(e){console.log(0)}})')"
    if [ "${n:-0}" -gt 0 ]; then
      pending="$(printf '%s' "$runs" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const r=JSON.parse(d);console.log(r.filter(x=>x.status!=="completed").length)})')"
      [ "$pending" -eq 0 ] && break
    fi
    sleep 10
  done
  if [ "${n:-0}" -eq 0 ]; then
    echo "check-dev: no workflow runs found for $sha (did the push touch app/**, supabase/**, terraform/** or a workflow file?)"
    runs="[]"
  fi
else
  runs="$(gh run list -R "$repo" --branch main --limit 6 --json databaseId,name,status,conclusion,url,headSha 2>/dev/null)"
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
