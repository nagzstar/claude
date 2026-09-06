#!/usr/bin/env bash
# Routing evals — does the Orchestrator pick the right team, tier and model?
#
#   bash evals/run-routing-evals.sh [--model <model>] [--only <case-id>]
#
# For each case in evals/routing-cases.json this runs the Orchestrator headlessly
# (`claude -p`) with the "ROUTE ONLY:" prefix defined in CLAUDE.md, which makes it emit a
# routing JSON and stop without executing. The JSON is compared with the case's `expect`.
#
# THIS COSTS TOKENS (one short orchestrator turn per case) — run it deliberately, not in CI.
# Run it with the model you actually use for the orchestrator session; routing quality is a
# property of that model. Results go to evals/results/<timestamp>.json.
#
# Requires the `claude` CLI on PATH. If you only use the VS Code extension, run this from a
# terminal where `claude` resolves.

set -u
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 2
model=""; only=""
while [ $# -gt 0 ]; do
  case "$1" in
    --model) model="$2"; shift 2 ;;
    --only) only="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
command -v claude >/dev/null 2>&1 || { echo "claude CLI not on PATH" >&2; exit 2; }

mkdir -p evals/results
out="evals/results/$(date +%Y%m%d-%H%M%S).json"
echo "[]" >"$out"

node -e '
  const cases = JSON.parse(require("fs").readFileSync("evals/routing-cases.json","utf8"));
  for (const c of cases) console.log(c.id);
' | while read -r id; do
  [ -n "$only" ] && [ "$only" != "$id" ] && continue
  prompt="$(node -e 'const c=JSON.parse(require("fs").readFileSync("evals/routing-cases.json","utf8")).find(x=>x.id===process.argv[1]);process.stdout.write("ROUTE ONLY: "+c.prompt)' "$id")"
  args=(-p --output-format json --permission-mode plan)
  [ -n "$model" ] && args+=(--model "$model")
  raw="$(claude "${args[@]}" "$prompt" 2>/dev/null)"
  node -e '
    const fs=require("fs"); const [id, out, rawArg] = process.argv.slice(1);
    const cases=JSON.parse(fs.readFileSync("evals/routing-cases.json","utf8")); const c=cases.find(x=>x.id===id);
    let text=""; try { const j=JSON.parse(rawArg); text = j.result || j.content || rawArg; } catch(e) { text = rawArg; }
    let got=null; const m = String(text).match(/\{[\s\S]*\}/); if (m) { try { got=JSON.parse(m[0]); } catch(e) {} }
    const e=c.expect; const problems=[];
    if (!got) problems.push("no routing JSON in output");
    else {
      if (e.tier && got.tier!==e.tier) problems.push(`tier ${got.tier} != ${e.tier}`);
      if (e.agents) { const g=(got.agents||[]); for (const a of e.agents) if (!g.includes(a)) problems.push(`missing agent ${a}`); }
      if (e.must_not_invoke) for (const a of e.must_not_invoke) if ((got.agents||[]).includes(a)) problems.push(`must not invoke ${a}`);
      if (e.parallel!==undefined && got.parallel!==e.parallel) problems.push(`parallel ${got.parallel} != ${e.parallel}`);
      if (e.orchestrator_does_it!==undefined && got.orchestrator_does_it!==e.orchestrator_does_it) problems.push(`orchestrator_does_it ${got.orchestrator_does_it} != ${e.orchestrator_does_it}`);
      if (e.stops_at && got.stops_at!==e.stops_at) problems.push(`stops_at ${got.stops_at} != ${e.stops_at}`);
      if (e.models) for (const [a,mdl] of Object.entries(e.models)) if ((got.models||{})[a]!==mdl) problems.push(`model for ${a}: ${(got.models||{})[a]} != ${mdl}`);
    }
    const res=JSON.parse(fs.readFileSync(out,"utf8")); res.push({id, pass: problems.length===0, problems, got}); fs.writeFileSync(out, JSON.stringify(res,null,2));
    console.log((problems.length? "FAIL ":"PASS ")+id+(problems.length? "  — "+problems.join("; "):""));
  ' "$id" "$out" "$raw"
done

node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));const p=r.filter(x=>x.pass).length;console.log(`routing evals: ${p}/${r.length} passed → ${process.argv[1]}`);process.exit(p===r.length?0:1)' "$out"
