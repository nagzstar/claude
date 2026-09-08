#!/usr/bin/env bash
# PreToolUse hook (matcher: Edit|Write|MultiEdit|NotebookEdit) declared in each specialist's
# frontmatter. Deterministic enforcement of file ownership so two agents can never edit the
# same file and a reviewer can never "fix" what it reviews.
#
#   usage: guard-paths.sh <role>
#   roles: frontend | backend | deployment | qa | researcher
#
# Paths outside NGM_ROOT and outside the Claude project directory (temp files) are allowed.
# Exit 2 blocks the edit with a message; exit 0 allows.

set -u
role="${1:-}"
input="$(cat)"

parsed="$(printf '%s' "$input" | node -e '
  let d = ""; process.stdin.on("data", c => d += c);
  process.stdin.on("end", () => {
    try {
      const j = JSON.parse(d); const t = j.tool_input || {};
      const c = String(t.content ?? t.new_string ?? "");
      process.stdout.write(c.length + " " + String(t.file_path || t.notebook_path || ""));
    } catch (e) { process.stdout.write("0 "); }
  });
' 2>/dev/null)"
bytes="${parsed%% *}"; path="${parsed#* }"
case "$bytes" in ''|*[!0-9]*) bytes=0 ;; esac

[ -z "$path" ] && exit 0

norm() { printf '%s' "$1" | sed -e 's#\\#/#g' -e 's#^\([A-Za-z]\):#/\L\1#' -e 's#^/\([a-z]\)/#/\1/#' | tr '[:upper:]' '[:lower:]'; }

p="$(norm "$path")"
ngm="$(norm "${NGM_ROOT:-$HOME/git/ngm.app}")"
proj="$(norm "${CLAUDE_PROJECT_DIR:-$PWD}")"

# Relative path → relative to the project dir (the working directory of the session).
case "$p" in
  /*) ;;
  *) p="$proj/$p" ;;
esac

# Only police files inside the two repos we care about.
rel=""
case "$p" in
  "$ngm"/*)  rel="${p#"$ngm"/}" ;;
  "$proj"/*) rel="${p#"$proj"/}" ;;
  *) exit 0 ;;
esac

deny() {
  echo "BLOCKED by guard-paths hook ($role): $rel is outside your ownership." >&2
  echo "Put the change you need in your report as a request for the owning agent; do not work around this." >&2
  exit 2
}

is_task_file() { printf '%s' "$rel" | grep -Eq '^\.agent-context/tasks/[^/]+\.md$'; }
is_test_file() { printf '%s' "$rel" | grep -Eq '(^app/src/test/|\.test\.(ts|tsx)$)'; }

case "$role" in
  frontend)
    is_task_file && exit 0
    printf '%s' "$rel" | grep -Eq '^(supabase|terraform|\.github|\.claude|\.agent-context)/' && deny
    printf '%s' "$rel" | grep -Eq '^claude\.md$' && deny
    exit 0 ;;
  backend)
    is_task_file && exit 0
    printf '%s' "$rel" | grep -Eq '^(\.github|\.claude|\.agent-context)/' && deny
    printf '%s' "$rel" | grep -Eq '^claude\.md$' && deny
    if printf '%s' "$rel" | grep -Eq '^app/'; then
      # Only the two cross-cutting files the Orchestrator may assign to backend.
      printf '%s' "$rel" | grep -Eq '^app/src/(integrations/supabase/types\.ts|types/index\.ts)$' || deny
    fi
    exit 0 ;;
  deployment)
    is_task_file && exit 0
    printf '%s' "$rel" | grep -Eq '^\.github/' && exit 0
    deny ;;
  qa)
    is_task_file && exit 0
    is_test_file && exit 0
    deny ;;
  researcher)
    # A design is a decision record, not a book: 28,000 bytes (≈ 400 lines). The five designs
    # of 2026-09-07 were 62–81 KB and each was read 3–7 times per run.
    if printf '%s' "$rel" | grep -Eq -- '-design\.md$' && [ "$bytes" -gt "${DESIGN_MAX_BYTES:-28000}" ]; then
      echo "BLOCKED by guard-paths hook (researcher): the design is ${bytes} bytes; the cap is ${DESIGN_MAX_BYTES:-28000}. Remove restated context and code listings (the engineers write the SQL); keep decisions, contract, authorization, ownership and the AC mapping." >&2
      exit 2
    fi
    printf '%s' "$rel" | grep -Eq '^\.agent-context/' && exit 0
    deny ;;
  *)
    echo "guard-paths: unknown role '$role' — allowing" >&2
    exit 0 ;;
esac
