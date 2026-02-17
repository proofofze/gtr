# gtr ─ Git worktree helper
#
# Examples
# --------
#   gtr create feature0          # add worktree (branch feat/feature0)
#   gtr create feat1 feat2       # add two worktrees at once
#   gtr rm feature0              # remove the worktree + branch
#   gtr rm -f feature0           # force-remove even if dirty
#   gtr cd feature0              # jump into the worktree directory
#   gtr list                     # list all worktrees
#   gtr claude feature0          # run `claude` inside that worktree
#   gtr help                     # show usage
#
# Configuration (env vars)
# ------------------------
#   GTR_WORKTREE_DIR   — base directory for worktrees (default: ~/code/worktrees)
#   GTR_BRANCH_PREFIX  — branch prefix (default: feat/)
#
GTR_VERSION="0.1.0"

# ------------------------------------------------------------

_gtr_copy_ignored_dirs () {
  local dest="$1"
  local src
  src="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0

  local dir
  for dir in .claude .prompts; do
    if [ -d "$src/$dir" ] && git check-ignore -q "$src/$dir" 2>/dev/null; then
      cp -R "$src/$dir" "$dest/$dir"
    fi
  done
}

gtr () {
  local cmd="$1"; shift || { gtr help; return 1; }

  # Configurable base folder and branch prefix
  local base="${GTR_WORKTREE_DIR:-$HOME/code/worktrees}"
  local prefix="${GTR_BRANCH_PREFIX:-feat/}"

  # Help and version don't require a git repo
  if [ "$cmd" = "version" ] || [ "$cmd" = "--version" ] || [ "$cmd" = "-v" ]; then
    echo "gtr $GTR_VERSION"
    return 0
  fi

  if [ "$cmd" = "help" ] || [ "$cmd" = "--help" ] || [ "$cmd" = "-h" ]; then
    cat <<'HELP'
gtr ─ Git worktree helper

Usage: gtr <command> [options] [name ...]

Commands:
  create <name> [name ...]   Create worktree(s) with branch $GTR_BRANCH_PREFIX<name>
                              Checks out existing branch if it already exists
  rm [-f] <name> [name ...]  Remove worktree(s) and their branches
                              -f / --force  force-remove even with uncommitted changes
  cd <name>                  Change directory into a worktree
  list, ls                   List worktrees in the base directory
  claude <name>              Open claude inside a worktree (creates if needed)
  version                    Show version
  help                       Show this help

Environment variables:
  GTR_WORKTREE_DIR    Base directory for worktrees (default: ~/code/worktrees)
  GTR_BRANCH_PREFIX   Branch prefix for new branches (default: feat/)

Examples:
  gtr create my-feature         # creates worktree + branch feat/my-feature
  gtr cd my-feature             # jump into it
  gtr rm my-feature             # clean remove
  gtr rm -f my-feature          # force remove (dirty worktree)
  GTR_BRANCH_PREFIX=fix/ gtr create bug42   # branch fix/bug42
HELP
    return 0
  fi

  # All other commands require a git repo
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "gtr: not inside a git repository" >&2
    return 1
  fi

  case "$cmd" in
    create)
      [ $# -gt 0 ] || { echo "Usage: gtr create <name> [name ...]"; return 1; }
      for name in "$@"; do
        local branch="${prefix}${name}"
        if git show-ref --verify --quiet "refs/heads/$branch"; then
          # Branch exists — check it out into the worktree
          git worktree add "$base/$name" "$branch" && _gtr_copy_ignored_dirs "$base/$name"
        elif git show-ref --verify --quiet "refs/heads/$name"; then
          # Bare name exists as a branch
          git worktree add "$base/$name" "$name" && _gtr_copy_ignored_dirs "$base/$name"
        else
          # Create new branch
          git worktree add "$base/$name" -b "$branch" && _gtr_copy_ignored_dirs "$base/$name"
        fi
      done
      ;;

    rm|remove)
      local force=0
      local names=()
      for arg in "$@"; do
        case "$arg" in
          -f|--force) force=1 ;;
          *) names+=("$arg") ;;
        esac
      done

      [ ${#names[@]} -gt 0 ] || { echo "Usage: gtr rm [-f] <name> [name ...]"; return 1; }

      for name in "${names[@]}"; do
        local wt_path="$base/$name"
        if [ "$force" -eq 1 ]; then
          git worktree remove --force "$wt_path" 2>/dev/null
          # Force-delete the branch, suppress errors if already gone
          git branch -D "${prefix}${name}" 2>/dev/null
          git branch -D "$name" 2>/dev/null
          echo "Removed worktree '$name' (forced)"
        else
          if git worktree remove "$wt_path" 2>/dev/null; then
            # Clean up branch, suppress errors if already deleted
            git branch -d "${prefix}${name}" 2>/dev/null
            git branch -d "$name" 2>/dev/null
            echo "Removed worktree '$name'"
          else
            echo "gtr: worktree '$name' has uncommitted changes:" >&2
            git -C "$wt_path" status --short 2>/dev/null
            echo "" >&2
            echo "Use 'gtr rm -f $name' to force-remove." >&2
            return 1
          fi
        fi
      done
      ;;

    cd)
      [ -n "$1" ] || { echo "Usage: gtr cd <name>"; return 1; }
      cd "$base/$1" || { echo "No such worktree: $base/$1"; return 1; }
      ;;

    list|ls)
      ls -1 "$base" 2>/dev/null || echo "No worktrees in $base"
      ;;

    claude)
      [ -n "$1" ] || { echo "Usage: gtr claude <name>"; return 1; }
      local dir="$base/$1"

      if [ ! -d "$dir" ]; then
        printf "Worktree '%s' doesn't exist. Create it now? [y/N] " "$1"
        read -r reply
        case "$reply" in
          [yY]|[yY][eE][sS])
            echo "Creating worktree '$1'…"
            local branch="${prefix}$1"
            if git show-ref --verify --quiet "refs/heads/$branch"; then
              git worktree add "$dir" "$branch" || { echo "git worktree add failed"; return 1; }
            elif git show-ref --verify --quiet "refs/heads/$1"; then
              git worktree add "$dir" "$1" || { echo "git worktree add failed"; return 1; }
            else
              git worktree add "$dir" -b "$branch" || { echo "git worktree add failed"; return 1; }
            fi
            _gtr_copy_ignored_dirs "$dir"
            ;;
          *)
            echo "Aborted."; return 1;;
        esac
      fi

      ( cd "$dir" && claude )
      ;;

    *)
      echo "Unknown sub-command: $cmd" >&2
      echo "Run 'gtr help' for usage." >&2
      return 1
      ;;
  esac
}

# --- Completion ---
if [ -n "$ZSH_VERSION" ]; then
  _gtr() {
    local base="${GTR_WORKTREE_DIR:-$HOME/code/worktrees}"

    if (( CURRENT == 2 )); then
      _values 'subcommand' create rm cd list ls claude version help
    elif (( CURRENT >= 3 )); then
      case "${words[2]}" in
        rm|cd|claude)
          local -a wts
          wts=("$base"/*(/:t))
          compadd -a wts
          ;;
      esac
    fi
  }
  compdef _gtr gtr
elif [ -n "$BASH_VERSION" ]; then
  _gtr_bash() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[1]}"
    local base="${GTR_WORKTREE_DIR:-$HOME/code/worktrees}"

    if [ "$COMP_CWORD" -eq 1 ]; then
      COMPREPLY=($(compgen -W "create rm cd list ls claude version help" -- "$cur"))
    elif [ "$COMP_CWORD" -ge 2 ]; then
      case "$prev" in
        rm|cd|claude)
          local wts
          if [ -d "$base" ]; then
            wts=$(ls -1 "$base" 2>/dev/null)
          fi
          COMPREPLY=($(compgen -W "$wts" -- "$cur"))
          ;;
      esac
    fi
  }
  complete -F _gtr_bash gtr
fi
