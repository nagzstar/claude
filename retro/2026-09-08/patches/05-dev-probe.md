# 05 — A committed DEV probe harness (A)

**Finding.** H6/F16: probe scripts were written from scratch in #12 (`ngm.js`, by the Orchestrator)
and #55 (`devprobe.sh`, 5 uses); sign-ins were hand-rolled in #12/#13; 5 `.env` denials (#3 ×2,
#13, #8, #33) were agents hunting for the anon key; #8 needed a 25-min orchestrator-only rerun to
validate DEV; #56 grepped the served bundle for a JWT and was denied.

**Expected effect.** One allow-listed script; QA (not the Orchestrator) runs role probes in one
loop; no `.env` reads; nothing printed but status codes and row counts. Saves ≈ 10–15 orchestrator
tool calls and ≈ 20 K output per issue; removes the `.env`-denial class.

New file `.claude/scripts/dev-probe.sh` (never prints a token or key):

```bash
#!/usr/bin/env bash
# DEV probe harness. Signs in as a test role and calls REST / RPC / storage on DEV; prints only
# HTTP status and a short body digest. Credentials come from the environment (names only here):
#   NGM_DEV_ADMIN_EMAIL / NGM_DEV_ADMIN_PASSWORD, NGM_DEV_MENTOR_*, NGM_DEV_PARTICIPANT_*
# The anon key is read from the served DEV bundle (it is public by design) and never echoed.
#
#   bash .claude/scripts/dev-probe.sh whoami <role>                     # sign in, print user id + role claims
#   bash .claude/scripts/dev-probe.sh rest <role> <method> <path> [json] # e.g. rest participant GET "/rest/v1/events?select=id&limit=3"
#   bash .claude/scripts/dev-probe.sh rpc  <role> <fn> [json]           # POST /rest/v1/rpc/<fn>
#   bash .claude/scripts/dev-probe.sh storage <role> <bucket> <object>  # GET object (expect 200 or 400/403)
#   bash .claude/scripts/dev-probe.sh matrix <method> <path>            # the same call as anon, participant, mentor, admin
# role: anon | participant | mentor | admin. Exit 0 always; the caller reads the statuses.
set -u
DEV="${NGM_DEV_URL:-https://dev.nextgenmaher.com}"
SB="${NGM_DEV_SUPABASE_URL:-https://qcpeqygsfhhzegsvzikp.supabase.co}"
cache="${TMPDIR:-/tmp}/ngm-dev-probe"; mkdir -p "$cache"
die() { echo "dev-probe: $*" >&2; exit 2; }
anon_key() {  # extracted from the served bundle; cached for the session; never printed
  if [ ! -s "$cache/anon" ]; then
    js="$(curl -sS "$DEV/" | grep -oE 'src="[^"]+\.js"' | head -1 | sed 's/src="//;s/"$//')"
    curl -sS "$DEV$js" | grep -oE 'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' | head -1 > "$cache/anon"
  fi
  [ -s "$cache/anon" ] || die "could not find the anon key in the served bundle"
  cat "$cache/anon"
}
token() {  # role -> access token (cached); reads NGM_DEV_<ROLE>_EMAIL/PASSWORD from the environment
  local role="$1" R; R="$(printf '%s' "$role" | tr '[:lower:]' '[:upper:]')"
  [ "$role" = anon ] && { printf ''; return; }
  if [ ! -s "$cache/tok-$role" ]; then
    local e p; e="$(eval "printf '%s' \"\${NGM_DEV_${R}_EMAIL:-}\"")"; p="$(eval "printf '%s' \"\${NGM_DEV_${R}_PASSWORD:-}\"")"
    [ -n "$e" ] && [ -n "$p" ] || die "NGM_DEV_${R}_EMAIL / NGM_DEV_${R}_PASSWORD are not set in this environment (see TEST-ACCOUNTS.md for where they live)"
    curl -sS -X POST "$SB/auth/v1/token?grant_type=password" -H "apikey: $(anon_key)" -H "content-type: application/json" \
      -d "$(node -e 'console.log(JSON.stringify({email:process.argv[1],password:process.argv[2]}))' "$e" "$p")" \
      | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{try{process.stdout.write(JSON.parse(d).access_token||"")}catch{}})' > "$cache/tok-$role"
    [ -s "$cache/tok-$role" ] || die "sign-in failed for role $role (status not 200 or no access_token)"
  fi
  cat "$cache/tok-$role"
}
call() {  # role method url [json] -> "STATUS <digest>"
  local role="$1" m="$2" url="$3" body="${4:-}" t; t="$(token "$role")"
  curl -sS -o "$cache/body" -w '%{http_code}' -X "$m" "$url" -H "apikey: $(anon_key)" ${t:+-H "Authorization: Bearer $t"} \
    -H "content-type: application/json" -H "prefer: return=representation" ${body:+-d "$body"} | tr -d '\n'
  printf ' %s\n' "$(node -e 'const fs=require("fs");let d=fs.readFileSync(process.argv[1],"utf8");try{const j=JSON.parse(d);process.stdout.write(Array.isArray(j)?`rows=${j.length}`:(j.message||j.msg||j.error||Object.keys(j).slice(0,6).join(",")).toString().slice(0,80))}catch{process.stdout.write(`bytes=${d.length}`)}' "$cache/body")"
}
case "${1:-}" in
  whoami)  call "$2" GET "$SB/auth/v1/user" ;;
  rest)    call "$2" "$3" "$SB$4" "${5:-}" ;;
  rpc)     call "$2" POST "$SB/rest/v1/rpc/$3" "${4:-{\}}" ;;
  storage) call "$2" GET "$SB/storage/v1/object/authenticated/$3/$4" ;;
  matrix)  for r in anon participant mentor admin; do printf '%-12s ' "$r"; call "$r" "$2" "$SB$3"; done ;;
  clear)   rm -rf "$cache" ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
```

```diff
--- a/.claude/settings.json
+++ b/.claude/settings.json
@@ -33,6 +33,7 @@
       "Bash(terraform plan:*)",
+      "Bash(bash .claude/scripts/dev-probe.sh:*)",
       "Bash(curl -sS:*)"
```

```diff
--- a/.claude/skills/ngm-facts/SKILL.md
+++ b/.claude/skills/ngm-facts/SKILL.md
@@ -83,6 +83,11 @@
 ## CI/CD principle
 
+## Validating on DEV
+
+`bash .claude/scripts/dev-probe.sh` signs in as `anon | participant | mentor | admin` from the
+`NGM_DEV_*` environment variables (names in `TEST-ACCOUNTS.md`, values never in the repo) and calls
+REST, RPC and storage on DEV, printing only statuses. Use it; never read `.env`, never write a
+probe script, never grep the bundle for keys. `matrix` runs one call as all four roles.
```

Also add to `qa-engineer.md` (after "## Method" or equivalent): "DEV validation is yours. Use
`dev-probe.sh` for every role-by-role authorization check; report the status matrix." `validate.sh`
section 5: `bash .claude/scripts/dev-probe.sh >/dev/null 2>&1; [ $? -eq 2 ] && ok` (usage exits 2
without network).
