#!/usr/bin/env bash
# Release <sha> to PROD as one command — ONLY after the user answered "Shall I deploy this to
# prod?" with an explicit yes and `prod-approval.sh grant <sha> "<their words>"` recorded it.
# Nothing here weakens the gate: every dispatch below is a plain `gh workflow run … -f
# environment=prod`, which guard-prod admits only from the main session under a fresh approval
# (a specialist calling this script is blocked at the first dispatch).
#
#   bash .claude/scripts/prod-release.sh <sha> [--terraform] [--no-db] [--no-app] [--record <task-file>]
#
# Order: terraform-apply.yml (only with --terraform) → database-migration.yml → deploy.yml, each
# `gh run watch`ed to success before the next. A failed run stops the script (exit 1) with the run
# id: diagnose (gh run view <id> --log-failed), rerun that workflow once by hand, else roll back.
# Then: read-only validation of https://nextgenmaher.com (HTTP status, served bundle name; nothing
# is created or deleted), `prod-approval.sh revoke`, and a release section appended to the task
# file named by --record with the run ids. Exit 2 = refused before any dispatch.
set -u
REPO="${NGM_REPO:-nagzstar/ngm.app}"; PROD="${NGM_PROD_URL:-https://nextgenmaher.com}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
proj="${CLAUDE_PROJECT_DIR:-$(cd "$here/../.." && pwd)}"
ngm="${NGM_ROOT:-$proj}"; [ -d "$proj/.git" ] && [ -f "$proj/app/package.json" ] && ngm="$proj"
usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
sha="${1:-}"; shift || true
tf=0; db=1; app=1; record=""
while [ $# -gt 0 ]; do
  case "$1" in
    --terraform) tf=1 ;; --no-db) db=0 ;; --no-app) app=0 ;;
    --record) record="${2:-}"; shift ;;
    *) echo "prod-release: unknown option $1" >&2; usage ;;
  esac; shift
done
printf '%s' "$sha" | grep -Eq '^[0-9a-f]{7,40}$' || usage
bash "$here/prod-approval.sh" status >/dev/null 2>&1 || { echo "prod-release: no active prod approval — ask \"Shall I deploy this to prod?\", then prod-approval.sh grant <sha> \"<the user's words>\"" >&2; exit 2; }
full="$(git -C "$ngm" rev-parse --verify "$sha^{commit}" 2>/dev/null)" || { echo "prod-release: unknown sha $sha in $ngm" >&2; exit 2; }
[ -n "$record" ] && [ ! -f "$record" ] && { echo "prod-release: --record file not found: $record" >&2; exit 2; }

status() { curl -sS -o /dev/null -w '%{http_code}' "$1" 2>/dev/null || echo "000"; }
echo "prod-release: $full → $PROD (pre-flight HTTP $(status "$PROD/"))"
ids=""
dispatch() { # workflow
  local wf="$1" id
  echo "dispatching $wf -f environment=prod (ref main at $full)"
  gh workflow run "$wf" -R "$REPO" -r main -f environment=prod || return 1
  sleep 10
  id="$(gh run list -R "$REPO" --workflow "$wf" --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null)"
  [ -n "$id" ] || { echo "prod-release: could not find the run for $wf" >&2; return 1; }
  if ! gh run watch "$id" -R "$REPO" --exit-status; then
    echo "RUN FAILED: $wf run $id — diagnose with: gh run view $id -R $REPO --log-failed; rerun once by hand, else roll back" >&2
    return 1
  fi
  ids="${ids:+$ids, }$wf=$id"
}
[ "$tf"  -eq 1 ] && { dispatch terraform-apply.yml     || exit 1; }
[ "$db"  -eq 1 ] && { dispatch database-migration.yml  || exit 1; }
[ "$app" -eq 1 ] && { dispatch deploy.yml              || exit 1; }

bundle="$(curl -sS "$PROD/" 2>/dev/null | grep -oE 'assets/index-[A-Za-z0-9_-]+\.js' | head -1)"
echo "validation (read-only): HTTP $(status "$PROD/"); bundle ${bundle:-not found}"
bash "$here/prod-approval.sh" revoke >/dev/null 2>&1 && echo "prod approval revoked"
if [ -n "$record" ]; then
  printf '\n## Prod release %s\n\nStatus: RELEASED TO PROD — sha `%s`; runs: %s. Validation: read-only, HTTP %s, bundle `%s`.\n' \
    "$(date -u +%Y-%m-%dT%H:%MZ)" "$full" "${ids:-none dispatched}" "$(status "$PROD/")" "${bundle:-?}" >> "$record"
  echo "recorded in $record"
fi
echo "RELEASED TO PROD: $full (${ids:-no workflow dispatched})"
