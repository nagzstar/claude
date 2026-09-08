#!/usr/bin/env bash
# DEV probe harness. Signs in as a test role and calls REST / RPC / storage on DEV; prints only
# the HTTP status and a short body digest. Credentials come from the environment (names only):
#   NGM_DEV_ADMIN_EMAIL / NGM_DEV_ADMIN_PASSWORD, NGM_DEV_MENTOR_*, NGM_DEV_PARTICIPANT_*
# The anon key is read from the served DEV bundle (public by design) and never echoed.
#
#   bash .claude/scripts/dev-probe.sh whoami <role>                      # sign in, print the user id
#   bash .claude/scripts/dev-probe.sh rest <role> <method> <path> [json]  # rest participant GET "/rest/v1/events?select=id&limit=3"
#   bash .claude/scripts/dev-probe.sh rpc  <role> <fn> [json]            # POST /rest/v1/rpc/<fn>
#   bash .claude/scripts/dev-probe.sh storage <role> <bucket> <object>   # GET the object (expect 200, or 400/403 when denied)
#   bash .claude/scripts/dev-probe.sh matrix <method> <path> [json]      # the same call as anon, participant, mentor, admin
#   bash .claude/scripts/dev-probe.sh body [max-bytes]                   # print the LAST response body (JWTs and token/password/secret fields redacted)
#   bash .claude/scripts/dev-probe.sh clear                              # forget cached tokens
# role: anon | participant | mentor | admin. Exit 0 always (read the statuses); exit 2 on usage.
# Never read .env for these values, never write a probe script, never grep the bundle for keys.
set -u
DEV="${NGM_DEV_URL:-https://dev.nextgenmaher.com}"
SB="${NGM_DEV_SUPABASE_URL:-https://qcpeqygsfhhzegsvzikp.supabase.co}"
cache="${TMPDIR:-/tmp}/ngm-dev-probe"; mkdir -p "$cache"
die() { echo "dev-probe: $*" >&2; exit 2; }
anon_key() {  # from the served bundle; cached; never printed
  if [ ! -s "$cache/anon" ]; then
    local js; js="$(curl -sS "$DEV/" | grep -oE 'src="[^"]+\.js"' | head -1 | sed 's/^src="//;s/"$//')"
    [ -n "$js" ] || die "could not find the app bundle on $DEV"
    case "$js" in http*) ;; /*) js="$DEV$js" ;; *) js="$DEV/$js" ;; esac
    curl -sS "$js" | grep -oE 'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' | head -1 > "$cache/anon"
  fi
  [ -s "$cache/anon" ] || die "could not find the anon key in the served bundle"
  cat "$cache/anon"
}
token() {  # role -> access token (cached); reads NGM_DEV_<ROLE>_EMAIL / _PASSWORD from the environment
  local role="$1" R e p; R="$(printf '%s' "$role" | tr '[:lower:]' '[:upper:]')"
  [ "$role" = anon ] && { printf ''; return; }
  case "$role" in participant|mentor|admin) ;; *) die "unknown role '$role' (anon | participant | mentor | admin)" ;; esac
  if [ ! -s "$cache/tok-$role" ]; then
    e="$(eval "printf '%s' \"\${NGM_DEV_${R}_EMAIL:-}\"")"; p="$(eval "printf '%s' \"\${NGM_DEV_${R}_PASSWORD:-}\"")"
    [ -n "$e" ] && [ -n "$p" ] || die "NGM_DEV_${R}_EMAIL / NGM_DEV_${R}_PASSWORD are not set in this environment (TEST-ACCOUNTS.md says where they live)"
    curl -sS -X POST "$SB/auth/v1/token?grant_type=password" -H "apikey: $(anon_key)" -H "content-type: application/json" \
      -d "$(node -e 'console.log(JSON.stringify({email:process.argv[1],password:process.argv[2]}))' "$e" "$p")" \
      | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{try{process.stdout.write(JSON.parse(d).access_token||"")}catch{}})' > "$cache/tok-$role"
    [ -s "$cache/tok-$role" ] || die "sign-in failed for role $role (no access_token returned)"
  fi
  cat "$cache/tok-$role"
}
call() {  # role method url [json] -> "STATUS digest"
  local role="$1" m="$2" url="$3" body="${4:-}" t; t="$(token "$role")"
  curl -sS -o "$cache/body" -w '%{http_code}' -X "$m" "$url" -H "apikey: $(anon_key)" ${t:+-H "Authorization: Bearer $t"} \
    -H "content-type: application/json" -H "prefer: return=representation" ${body:+-d "$body"} | tr -d '\n'
  printf ' %s\n' "$(node -e '
    const fs=require("fs");const d=fs.readFileSync(process.argv[1],"utf8");
    // Redact anything credential-shaped before ANY of it can reach a transcript.
    const SECRET=/^(.*(token|password|apikey|api_key|secret|authorization).*)$/i;
    const scrub=v=>typeof v==="string"&&/^ey[A-Za-z0-9_-]{8,}\./.test(v)?"<redacted>":v;
    const pair=(k,v)=>SECRET.test(k)?`${k}=<redacted>`:`${k}=${JSON.stringify(scrub(v)).slice(0,60)}`;
    const digest=j=>{
      if(Array.isArray(j)) return `rows=${j.length}`;
      const named=j.message||j.msg||j.error;
      if(named) return String(named).slice(0,80);
      // Print key=value for scalar fields, not just the key names: an id-like field
      // under any name (runId, run_id, cursor, status) is usually the point of the call.
      const out=Object.entries(j).filter(([,v])=>v===null||typeof v!=="object")
        .slice(0,6).map(([k,v])=>pair(k,v)).join(" ");
      return (out||Object.keys(j).slice(0,6).join(",")).slice(0,200);
    };
    try{process.stdout.write(digest(JSON.parse(d)))}catch{process.stdout.write(`bytes=${d.length}`)}
  ' "$cache/body")"
}
show_body() {  # print the last response body, credential-scrubbed and capped
  [ -s "$cache/body" ] || die "no cached response body yet — make a call first"
  node -e '
    const fs=require("fs");const cap=Number(process.argv[2])||4000;
    let d=fs.readFileSync(process.argv[1],"utf8");
    d=d.replace(/ey[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g,"<redacted-jwt>")
       .replace(/("(?:[^"]*(?:token|password|apikey|api_key|secret)[^"]*)"\s*:\s*)"[^"]*"/gi,"$1\"<redacted>\"");
    process.stdout.write(d.length>cap?d.slice(0,cap)+`\n… truncated (${d.length} bytes)`:d);
  ' "$cache/body" "${1:-4000}"
  printf '\n'
}
case "${1:-}" in
  whoami)  [ $# -ge 2 ] || die "whoami <role>"; call "$2" GET "$SB/auth/v1/user" ;;
  rest)    [ $# -ge 4 ] || die "rest <role> <method> <path> [json]"; call "$2" "$3" "$SB$4" "${5:-}" ;;
  rpc)     [ $# -ge 3 ] || die "rpc <role> <fn> [json]"; call "$2" POST "$SB/rest/v1/rpc/$3" "${4:-{\}}" ;;
  storage) [ $# -ge 4 ] || die "storage <role> <bucket> <object>"; call "$2" GET "$SB/storage/v1/object/authenticated/$3/$4" ;;
  matrix)  [ $# -ge 3 ] || die "matrix <method> <path> [json]"; for r in anon participant mentor admin; do printf '%-12s ' "$r"; call "$r" "$2" "$SB$3" "${4:-}"; done ;;
  body)    show_body "${2:-4000}" ;;
  clear)   rm -rf "$cache"; echo "cleared" ;;
  *) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
