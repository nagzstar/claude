#!/usr/bin/env bash
# Deterministic self-test of the agent system. No model calls, no tokens. Run before
# committing a change to this repo, and in CI.
#
#   bash scripts/validate.sh
#
# Checks: agent frontmatter is well-formed and models are from the approved set; every
# specialist preloads the standing rules and (if it can edit) carries the ownership hook;
# CLAUDE.md and the docs reference only agents that exist; settings.json parses and its hooks
# point at real scripts; hook scripts block/allow the right commands and paths; the install
# manifest matches the repo; eval cases reference real agents.

set -u
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 2
export CLAUDE_PROJECT_DIR="$root"
export NGM_ROOT="${NGM_ROOT:-C:/Users/nagaj/git/ngm.app}"

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $*"; }

allowed_models="claude-sonnet-5 claude-opus-5 claude-fable-5-1 claude-haiku-4-5 sonnet opus fable haiku inherit"

# ---- 1. agents ---------------------------------------------------------------------------
agents=""
for f in .claude/agents/*.md; do
  base="$(basename "$f" .md)"
  fm="$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}' "$f")"
  name="$(printf '%s\n' "$fm" | grep -E '^name:' | sed 's/^name:[[:space:]]*//')"
  model="$(printf '%s\n' "$fm" | grep -E '^model:' | sed 's/^model:[[:space:]]*//')"
  desc="$(printf '%s\n' "$fm" | grep -E '^description:' | sed 's/^description:[[:space:]]*//')"
  tools="$(printf '%s\n' "$fm" | grep -E '^tools:' | sed 's/^tools:[[:space:]]*//')"
  [ "$name" = "$base" ] && ok || bad "$f: name '$name' != filename '$base'"
  [ -n "$desc" ] && ok || bad "$f: missing description"
  [ -n "$tools" ] && ok || bad "$f: missing tools"
  if [ -n "$model" ] && printf ' %s ' "$allowed_models" | grep -q " $model "; then ok; else bad "$f: model '$model' not in approved set"; fi
  printf '%s\n' "$fm" | grep -qE '^\s*-\s*ngm-standing-rules' && ok || bad "$f: does not preload ngm-standing-rules"
  if printf '%s' "$tools" | grep -qE '\b(Edit|Write)\b'; then
    printf '%s\n' "$fm" | grep -q 'guard-paths.sh' && ok || bad "$f: has Edit/Write but no guard-paths hook"
  else
    printf '%s\n' "$fm" | grep -q 'guard-paths.sh' && bad "$f: read-only agent carries a paths hook (harmless but confusing)" || ok
  fi
  [ "$(wc -c <"$f")" -lt 9000 ] && ok || bad "$f: over 9 kB — trim it"
  agents="$agents $base"
done
[ -f .claude/agents/qa-security.md ] && bad "stale qa-security.md still present"

# ---- 2. references ------------------------------------------------------------------------
for a in $agents; do grep -q "\`$a\`" CLAUDE.md && ok || bad "CLAUDE.md does not mention $a"; done
for stale in qa-security; do
  hits="$(grep -rl --exclude-dir=.git --exclude-dir=node_modules --exclude=CHANGELOG.md "$stale" . 2>/dev/null | grep -v '^./scripts/validate.sh$' || true)"
  [ -z "$hits" ] && ok || bad "stale agent name '$stale' referenced in: $(echo "$hits" | tr '\n' ' ')"
done
for s in .claude/skills/*/SKILL.md; do
  d="$(basename "$(dirname "$s")")"; n="$(grep -E '^name:' "$s" | head -1 | sed 's/^name:[[:space:]]*//')"
  [ "$n" = "$d" ] && ok || bad "$s: skill name '$n' != dir '$d'"
done
[ "$(wc -c <CLAUDE.md)" -lt 15000 ] && ok || bad "CLAUDE.md over 15 kB — it is always in context"

# ---- 3. settings + hooks ------------------------------------------------------------------
node -e 'JSON.parse(require("fs").readFileSync(".claude/settings.json","utf8"))' 2>/dev/null && ok || bad "settings.json is not valid JSON"
for h in $(grep -oE '\.claude/hooks/[a-z-]+\.sh' .claude/settings.json .claude/agents/*.md | sed 's/.*:\(\.claude\)/\1/' | sort -u); do
  [ -f "$h" ] && ok || bad "hook script missing: $h"
done
node -e 'JSON.parse(require("fs").readFileSync(".agent-context/baseline.json","utf8")).lint.errors' >/dev/null 2>&1 && ok || bad "baseline.json malformed"
for s in .claude/hooks/*.sh .claude/scripts/*.sh scripts/*.sh evals/*.sh; do
  [ -f "$s" ] || continue
  bash -n "$s" && ok || bad "$s: syntax error"
  grep -q $'\r' "$s" && bad "$s: has CRLF line endings (bash will break)" || ok
done

# ---- 4. hook behaviour --------------------------------------------------------------------
# The prod approval token is redirected to a scratch file so the tests never touch a real one.
export PROD_APPROVAL_FILE="$(mktemp -t ngm-prod-approval.XXXXXX)"; rm -f "$PROD_APPROVAL_FILE"
prod() { # expect cmd [agent]
  local exp="$1" cmd="$2" agent="${3:-}" rc extra=""
  [ -n "$agent" ] && extra=",\"agent_id\":\"$agent\",\"agent_type\":\"$agent\""
  printf '{"tool_name":"Bash","tool_input":{"command":%s}%s}' "$(node -e 'console.log(JSON.stringify(process.argv[1]))' "$cmd")" "$extra" \
    | bash .claude/hooks/guard-prod.sh >/dev/null 2>&1; rc=$?
  if { [ "$exp" = block ] && [ $rc -eq 2 ]; } || { [ "$exp" = allow ] && [ $rc -eq 0 ]; }; then ok; else bad "guard-prod: expected $exp for: $cmd${agent:+ (agent $agent)} (rc=$rc)"; fi
}
# No approval recorded: every prod dispatch is blocked.
prod block 'gh workflow run deploy.yml -f environment=prod'
prod block 'gh workflow run terraform-apply.yml --field environment=prod'
prod block 'gh api repos/nagzstar/ngm.app/actions/workflows/deploy.yml/dispatches -f inputs[environment]=prod'
prod block 'curl -X POST https://api.github.com/repos/x/y/actions/workflows/deploy.yml/dispatches -d "{\"inputs\":{\"environment\":\"prod\"}}"'
# Approval recorded by the script: the main session may dispatch prod; a subagent never may.
bash .claude/scripts/prod-approval.sh grant 0123abc "yes, deploy it" >/dev/null 2>&1 && ok || bad "prod-approval.sh grant failed"
bash .claude/scripts/prod-approval.sh status >/dev/null 2>&1 && ok || bad "prod-approval.sh status should succeed while active"
prod allow 'gh workflow run deploy.yml -f environment=prod'
prod block 'gh workflow run deploy.yml -f environment=prod' deployment-engineer
prod block 'terraform apply -auto-approve'   # an approval never unlocks direct deploys
grep -q '^admitted_epoch=' "$PROD_APPROVAL_FILE" && ok || bad "guard-prod did not log the admitted prod command"
bash .claude/scripts/prod-approval.sh revoke >/dev/null 2>&1 && ok || bad "prod-approval.sh revoke failed"
[ ! -f "$PROD_APPROVAL_FILE" ] && ok || bad "revoke left the approval file behind"
prod block 'gh workflow run deploy.yml -f environment=prod'
# An expired approval is blocked and cleared.
printf 'granted_epoch=1\nsha=0123abc\n' > "$PROD_APPROVAL_FILE"
prod block 'gh workflow run deploy.yml -f environment=prod'
[ ! -f "$PROD_APPROVAL_FILE" ] && ok || bad "guard-prod did not clear an expired approval"
bash .claude/scripts/prod-approval.sh grant notasha "yes" >/dev/null 2>&1 && bad "grant accepted a non-sha" || ok
bash .claude/scripts/prod-approval.sh grant 0123abc >/dev/null 2>&1 && bad "grant accepted a missing quote" || ok
prod allow 'gh workflow run deploy.yml -f environment=dev'
prod allow 'gh workflow run terraform-apply.yml -f environment=dev'
prod block 'terraform apply -auto-approve'
prod block 'terraform destroy'
prod allow 'terraform plan'
prod block 'npx wrangler pages deploy dist'
prod block 'supabase db push'
prod block 'supabase db reset'
prod block 'supabase functions deploy'
prod block 'git push --force'
prod block 'git push -f origin main'
prod block 'git push origin main --force-with-lease'
prod allow 'git push origin main'
prod allow 'gh run list -R nagzstar/ngm.app'
prod block 'gh run rerun notanumber'

paths() { # expect role path
  local exp="$1" role="$2" p="$3" rc
  printf '{"tool_name":"Edit","tool_input":{"file_path":%s}}' "$(node -e 'console.log(JSON.stringify(process.argv[1]))' "$p")" \
    | bash .claude/hooks/guard-paths.sh "$role" >/dev/null 2>&1; rc=$?
  if { [ "$exp" = block ] && [ $rc -eq 2 ]; } || { [ "$exp" = allow ] && [ $rc -eq 0 ]; }; then ok; else bad "guard-paths: expected $exp for $role $p (rc=$rc)"; fi
}
N="$NGM_ROOT"
paths allow frontend "$N/app/src/pages/LoginPage.tsx"
paths allow frontend 'C:\Users\nagaj\git\ngm.app\app\src\contexts\AuthContext.tsx'
paths block frontend "$N/supabase/migrations/x.sql"
paths block frontend "$N/.github/workflows/deploy.yml"
paths block frontend "$root/CLAUDE.md"
paths allow frontend "$N/.agent-context/tasks/t.md"
paths allow backend "$N/supabase/migrations/x.sql"
paths allow backend "$N/terraform/main.tf"
paths allow backend "$N/app/src/integrations/supabase/types.ts"
paths allow backend "$N/app/src/types/index.ts"
paths block backend "$N/app/src/contexts/AuthContext.tsx"
paths block backend "$N/.github/workflows/deploy.yml"
paths allow deployment "$N/.github/workflows/deploy.yml"
paths block deployment "$N/app/src/App.tsx"
paths block deployment "$N/terraform/main.tf"
paths allow qa "$N/app/src/test/x.test.tsx"
paths allow qa "$N/app/src/pages/X.test.tsx"
paths block qa "$N/app/src/pages/X.tsx"
paths block qa "$N/supabase/migrations/x.sql"
paths allow researcher "$N/.agent-context/tasks/design.md"
paths block researcher "$N/app/src/App.tsx"
paths allow qa "C:/Users/nagaj/AppData/Local/Temp/scratch.txt"

# ---- 5. install manifest + evals -----------------------------------------------------------
for d in .claude/agents .claude/skills .claude/hooks .claude/scripts .agent-context .agent-context/tasks; do
  grep -q "$d" scripts/install-into-repo.ps1 && ok || bad "install script does not handle $d"
done
if [ -f evals/routing-cases.json ]; then
  node -e '
    const fs=require("fs"); const cases=JSON.parse(fs.readFileSync("evals/routing-cases.json","utf8"));
    const agents=fs.readdirSync(".claude/agents").map(f=>f.replace(/\.md$/,"")).concat(["Explore"]);
    let bad=0;
    for (const c of cases) {
      if (!c.id || !c.prompt || !c.expect) { console.log("case missing id/prompt/expect: "+JSON.stringify(c).slice(0,80)); bad++; continue; }
      for (const a of (c.expect.agents||[])) if (!agents.includes(a)) { console.log(`case ${c.id}: unknown agent ${a}`); bad++; }
      for (const a of (c.expect.must_not_invoke||[])) if (!agents.includes(a)) { console.log(`case ${c.id}: unknown agent ${a}`); bad++; }
      if (c.expect.tier && ![1,2,3,4].includes(c.expect.tier)) { console.log(`case ${c.id}: bad tier`); bad++; }
    }
    process.exit(bad?1:0);
  ' && ok || bad "evals/routing-cases.json has problems (see above)"
fi

echo "validate: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
