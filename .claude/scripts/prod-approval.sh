#!/usr/bin/env bash
# Records, shows or revokes the user's approval for a PROD release. The guard-prod hook admits
# a prod dispatch or prod rerun only while a fresh approval exists (default 60 minutes), and
# only from the main session — never from a subagent.
#
#   bash .claude/scripts/prod-approval.sh grant <sha> "<the user's exact words>"
#   bash .claude/scripts/prod-approval.sh status
#   bash .claude/scripts/prod-approval.sh revoke
#
# POLICY, not mechanics: run `grant` only after you have reported READY FOR PROD, asked the
# user "Shall I deploy this to prod?" and received an explicit yes in the conversation.
# Silence, "looks good", or an instruction given before DEV was validated is not a yes.
# Quote the user's actual words — they go into the task record as the audit trail.
# Run `revoke` as soon as the release is validated (or abandoned).

set -u
file="${PROD_APPROVAL_FILE:-${CLAUDE_PROJECT_DIR:-$PWD}/.agent-context/.prod-approval}"
ttl="${PROD_APPROVAL_TTL:-3600}"

case "${1:-}" in
  grant)
    sha="${2:-}"; words="${3:-}"
    if [ -z "$sha" ] || [ -z "$words" ]; then
      echo "usage: prod-approval.sh grant <sha> \"<the user's exact words>\"" >&2; exit 2
    fi
    if ! printf '%s' "$sha" | grep -Eq '^[0-9a-f]{7,40}$'; then
      echo "grant: '$sha' is not a commit sha" >&2; exit 2
    fi
    mkdir -p "$(dirname "$file")"
    {
      printf 'granted_epoch=%s\n' "$(date +%s)"
      printf 'granted_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf 'sha=%s\n' "$sha"
      printf 'user_said=%s\n' "$words"
    } > "$file"
    echo "prod approval recorded for $sha; valid for $((ttl / 60)) minutes. Revoke it when the release is validated."
    ;;
  status)
    if [ ! -f "$file" ]; then echo "no prod approval recorded"; exit 1; fi
    granted="$(grep -E '^granted_epoch=' "$file" | head -1 | cut -d= -f2)"
    age=$(( $(date +%s) - ${granted:-0} ))
    if [ "$age" -gt "$ttl" ]; then echo "prod approval EXPIRED ($((age / 60)) minutes old)"; cat "$file"; exit 1; fi
    echo "prod approval active ($((age / 60)) minutes old, expires in $(( (ttl - age) / 60 )) minutes)"
    cat "$file"
    ;;
  revoke)
    if [ -f "$file" ]; then
      echo "revoking prod approval; commands it admitted:"
      grep -E '^admitted_epoch=' "$file" || echo "  (none)"
      rm -f "$file"
    else
      echo "no prod approval to revoke"
    fi
    ;;
  *)
    echo "usage: prod-approval.sh grant <sha> \"<user's words>\" | status | revoke" >&2; exit 2 ;;
esac
