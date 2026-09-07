#!/usr/bin/env bash
# Deterministic GitHub-issue plumbing for the NGM backlog (nagzstar/ngm.app/issues). Used by
# the Project Manager mode (skill ngm-project-manager) and by feature sessions started with
# pm-run-issue.sh, so that labels, statuses and comment formats are the same everywhere.
# No model calls. Needs an authenticated `gh` with repo scope; nothing here needs Projects.
#
#   bash .claude/scripts/pm-issue.sh labels                      # create any missing labels (idempotent)
#   bash .claude/scripts/pm-issue.sh list [--all]                # backlog table by priority + status
#   bash .claude/scripts/pm-issue.sh show <n>                    # body + every comment (read it all)
#   bash .claude/scripts/pm-issue.sh status <n> <status|none>    # set the single workflow status label
#   bash .claude/scripts/pm-issue.sh priority <n> <P1|P2|P3|none>
#   bash .claude/scripts/pm-issue.sh comment <n> <file>          # post a comment from a markdown file
#   bash .claude/scripts/pm-issue.sh new <type> "<title>" <body-file> [found-in-issue]
#                                                                # file a bug/idea, labelled claude + <type>
#
# Statuses (one at a time; none = an unrefined idea):
#   needs-info → ready → in-progress → ready-for-prod | needs-decision | blocked → (closed = released)
# Type labels: feature bug improvement infrastructure security ui admin mobile.
# `claude` marks anything Claude filed on its own initiative (bugs, ideas, problems spotted).

set -u
REPO="${NGM_REPO:-nagzstar/ngm.app}"
STATUSES="needs-info ready in-progress ready-for-prod needs-decision blocked"
PRIORITIES="P1 P2 P3"
TYPES="feature bug improvement infrastructure security ui admin mobile"

die() { echo "pm-issue: $*" >&2; exit 2; }
need_gh() { gh auth status >/dev/null 2>&1 || die "gh is not authenticated"; }
is_number() { printf '%s' "${1:-}" | grep -Eq '^[0-9]+$'; }
has_word() { printf ' %s ' "$1" | grep -q " $2 "; }

# name|color|description — kept here so a fresh checkout can recreate the set.
label_defs() {
  cat <<'EOF'
claude|8250df|Filed by Claude during a task: a bug, idea or problem spotted
needs-info|fbca04|Being fleshed out with the user; not ready to build
ready|0e8a16|Fleshed out and agreed; a feature session can pick it up
in-progress|1d76db|A feature session is working on it
ready-for-prod|0052cc|Validated on DEV; waiting for the user's prod decision
needs-decision|d93f0b|Waiting on a decision only the user can make (see latest comment)
blocked|b60205|Blocked; see the latest comment
P1|b60205|Priority 1: next up
P2|e99695|Priority 2: after P1
P3|f9d0c4|Priority 3: later
feature|0e8a16|New capability for users
bug|d73a4a|Something isn't working
improvement|a2eeef|Improvement to something that already exists
infrastructure|c5def5|Pipelines, Terraform, hosting, environments
security|ee0701|Authorization, RLS, secrets, abuse
ui|1d76db|User interface and UX
admin|5319e7|Admin-facing features and moderation
mobile|bfd4f2|PWA / mobile shell / push
EOF
}

cmd="${1:-}"; shift || true
case "$cmd" in
  labels)
    need_gh
    existing="$(gh label list -R "$REPO" --limit 200 --json name --jq '.[].name')"
    label_defs | while IFS='|' read -r name color desc; do
      if printf '%s\n' "$existing" | grep -qx "$name"; then
        echo "  exists  $name"
      else
        gh label create "$name" -R "$REPO" --color "$color" --description "$desc" >/dev/null && echo "  created $name"
      fi
    done
    ;;

  list)
    need_gh
    state="open"; [ "${1:-}" = "--all" ] && state="all"
    gh issue list -R "$REPO" --state "$state" --limit 200 --json number,title,labels,state,updatedAt \
      | node -e '
        let d=""; process.stdin.on("data",c=>d+=c); process.stdin.on("end",()=>{
          const S=["in-progress","ready-for-prod","needs-decision","blocked","ready","needs-info"];
          const rows=JSON.parse(d).map(i=>{
            const l=i.labels.map(x=>x.name);
            const p=l.find(x=>/^P[123]$/.test(x))||"--";
            const s=S.find(x=>l.includes(x))||(i.state==="CLOSED"?"closed":"idea");
            const t=l.filter(x=>!/^P[123]$/.test(x)&&!S.includes(x)).join(",");
            return {n:i.number,p,s,t,title:i.title,state:i.state};
          });
          const rank=r=>[r.p==="--"?9:Number(r.p[1]), r.s==="idea"?S.length:S.indexOf(r.s), r.n];
          rows.sort((a,b)=>{const x=rank(a),y=rank(b);for(let i=0;i<3;i++){if(x[i]!==y[i])return x[i]-y[i];}return 0;});
          console.log("#     P   status          labels                         title");
          for(const r of rows) console.log(String(r.n).padEnd(5)+" "+r.p.padEnd(3)+" "+r.s.padEnd(15)+" "+r.t.slice(0,30).padEnd(30)+" "+r.title);
          console.log(`\n${rows.length} issue(s). Statuses: none=idea, needs-info, ready, in-progress, ready-for-prod, needs-decision, blocked.`);
        });'
    ;;

  show)
    need_gh; is_number "${1:-}" || die "show needs an issue number"
    gh issue view "$1" -R "$REPO"
    echo; echo "----- comments -----"
    gh issue view "$1" -R "$REPO" --comments
    ;;

  status)
    need_gh; is_number "${1:-}" || die "status needs an issue number"
    new="${2:-}"; [ -n "$new" ] || die "status needs one of: $STATUSES none"
    [ "$new" = none ] || has_word "$STATUSES" "$new" || die "unknown status '$new' (use: $STATUSES none)"
    rm=""; for s in $STATUSES; do [ "$s" = "$new" ] || rm="$rm --remove-label $s"; done
    add=""; [ "$new" = none ] || add="--add-label $new"
    # shellcheck disable=SC2086
    gh issue edit "$1" -R "$REPO" $rm $add >/dev/null && echo "#$1 status → $new"
    ;;

  priority)
    need_gh; is_number "${1:-}" || die "priority needs an issue number"
    new="${2:-}"; [ -n "$new" ] || die "priority needs one of: $PRIORITIES none"
    [ "$new" = none ] || has_word "$PRIORITIES" "$new" || die "unknown priority '$new'"
    rm=""; for p in $PRIORITIES; do [ "$p" = "$new" ] || rm="$rm --remove-label $p"; done
    add=""; [ "$new" = none ] || add="--add-label $new"
    # shellcheck disable=SC2086
    gh issue edit "$1" -R "$REPO" $rm $add >/dev/null && echo "#$1 priority → $new"
    ;;

  comment)
    need_gh; is_number "${1:-}" || die "comment needs an issue number"
    [ -f "${2:-}" ] || die "comment needs a markdown file as the body"
    gh issue comment "$1" -R "$REPO" --body-file "$2"
    ;;

  new)
    need_gh
    type="${1:-}"; title="${2:-}"; body="${3:-}"; from="${4:-}"
    has_word "$TYPES" "$type" || die "new needs a type: $TYPES"
    [ -n "$title" ] || die "new needs a title"
    [ -f "$body" ] || die "new needs a body file (markdown: ## Idea / ## Notes)"
    tmp="$(mktemp)"
    cat "$body" > "$tmp"
    if [ -n "$from" ]; then printf '\n\n_Found while working on #%s._\n' "$from" >> "$tmp"; fi
    url="$(gh issue create -R "$REPO" --title "$title" --label "claude,$type" --body-file "$tmp")"
    rm -f "$tmp"
    echo "$url"
    ;;

  *)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
