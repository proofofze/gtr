# gtr ─ Git worktree helper
#
# Examples
# --------
#   gtr create feature0              # add worktree (branch feat/feature0)
#   gtr create feature0 hotfix/      # add worktree (branch hotfix/feature0)
#   gtr rm feature0                  # remove the worktree + branch
#   gtr rm -f feature0               # force-remove even if dirty
#   gtr cd feature0                  # jump into the worktree directory
#   gtr cd                           # jump back to the main worktree
#   gtr main                         # jump back to the main worktree
#   gtr list                         # list all worktrees (paths, commits, branches)
#   gtr claude feature0              # run `claude` inside that worktree
#   gtr config                       # show current base path and source
#   gtr config /path/to/worktrees    # persist base path to config file
#   gtr help                         # show usage
#
# Configuration (resolution order)
# --------------------------------
#   1. GTR_WORKTREE_DIR env var
#   2. ~/.config/gtr/config file
#   3. Auto-detect: <git-root>/../worktrees
#   4. Fallback: ~/code/worktrees
#
#   GTR_BRANCH_PREFIX  — branch prefix (default: feat/)
#
GTR_VERSION="1.2.0"

# ------------------------------------------------------------

_gtr_validate_name () {
  local name="$1"
  if [ -z "$name" ]; then
    echo "gtr: name cannot be empty" >&2; return 1
  fi
  if [ "${name#-}" != "$name" ]; then
    echo "gtr: name cannot start with '-': $name" >&2; return 1
  fi
  case "$name" in
    *..* | */* | *\\*)
      echo "gtr: name cannot contain '..', '/' or '\\': $name" >&2; return 1 ;;
  esac
}

_gtr_base_path () {
  # 1. Env var (highest priority)
  if [ -n "$GTR_WORKTREE_DIR" ]; then
    echo "$GTR_WORKTREE_DIR"
    return
  fi
  # 2. Config file
  if [ -f "$HOME/.config/gtr/config" ]; then
    local cfg
    cfg="$(cat "$HOME/.config/gtr/config")"
    if [ -n "$cfg" ]; then
      echo "$cfg"
      return
    fi
  fi
  # 3. Auto-detect: <git-root>/../worktrees
  local git_root
  git_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$git_root" ]; then
    local auto_dir
    auto_dir="$(cd "$git_root/.." && pwd)/worktrees"
    if [ -d "$auto_dir" ]; then
      echo "$auto_dir"
      return
    fi
  fi
  # 4. Fallback
  echo "$HOME/code/worktrees"
}

_gtr_base_path_source () {
  if [ -n "$GTR_WORKTREE_DIR" ]; then
    echo "env GTR_WORKTREE_DIR"
    return
  fi
  if [ -f "$HOME/.config/gtr/config" ]; then
    local cfg
    cfg="$(cat "$HOME/.config/gtr/config")"
    if [ -n "$cfg" ]; then
      echo "config file (~/.config/gtr/config)"
      return
    fi
  fi
  local git_root
  git_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$git_root" ]; then
    local auto_dir
    auto_dir="$(cd "$git_root/.." && pwd)/worktrees"
    if [ -d "$auto_dir" ]; then
      echo "auto-detected (<git-root>/../worktrees)"
      return
    fi
  fi
  echo "default (~/code/worktrees)"
}

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

  # Configurable branch prefix
  local prefix="${GTR_BRANCH_PREFIX:-feat/}"

  # Help and version don't require a git repo
  if [ "$cmd" = "version" ] || [ "$cmd" = "--version" ] || [ "$cmd" = "-v" ]; then
    echo "gtr $GTR_VERSION"
    return 0
  fi

  if [ "$cmd" = "help" ] || [ "$cmd" = "--help" ] || [ "$cmd" = "-h" ]; then
    cat <<'HELP'
gtr ─ Git worktree helper

Usage: gtr <command> [options] [args]

Commands:
  create <name> [prefix]   Create worktree with branch <prefix><name>
                             Default prefix from $GTR_BRANCH_PREFIX (feat/)
                             Checks out existing branch if it already exists
  rm [-f] <name> [name ...] Remove worktree(s) and their branches
                             -f / --force  force-remove even with uncommitted changes
  cd [name]                 Change directory into a worktree (main worktree if no name)
  main                      Change directory to the main worktree
  list, ls                  List worktrees (paths, commits, branches)
  claude <name>             Open claude inside a worktree (creates if needed)
  config [path]             Show or set the worktrees base directory
  version                   Show version
  help                      Show this help

Base path resolution (first match wins):
  1. $GTR_WORKTREE_DIR env var
  2. ~/.config/gtr/config file
  3. Auto-detect: <git-root>/../worktrees (if it exists)
  4. Fallback: ~/code/worktrees

Environment variables:
  GTR_WORKTREE_DIR    Override base directory for worktrees
  GTR_BRANCH_PREFIX   Branch prefix for new branches (default: feat/)

Examples:
  gtr create my-feature              # creates branch feat/my-feature
  gtr create my-feature hotfix/      # creates branch hotfix/my-feature
  gtr cd my-feature                  # jump into it
  gtr cd                             # jump back to main worktree
  gtr main                           # jump back to main worktree
  gtr list                           # show all worktrees with details
  gtr rm my-feature                  # clean remove
  gtr rm -f my-feature               # force remove (dirty worktree)
  gtr config                         # show current base path and source
  gtr config ~/projects/worktrees    # persist base path
HELP
    return 0
  fi

  # Config doesn't require a git repo
  if [ "$cmd" = "config" ]; then
    if [ -z "$1" ]; then
      echo "Base path: $(_gtr_base_path)"
      echo "Source:    $(_gtr_base_path_source)"
    else
      mkdir -p "$HOME/.config/gtr"
      printf '%s' "$1" > "$HOME/.config/gtr/config"
      echo "Saved base path: $1"
      echo "Config file: ~/.config/gtr/config"
    fi
    return 0
  fi

  # All other commands require a git repo
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "gtr: not inside a git repository" >&2
    return 1
  fi

  local base
  base="$(_gtr_base_path)"

  case "$cmd" in
    create)
      [ $# -gt 0 ] || { echo "Usage: gtr create <name> [prefix]"; return 1; }
      local name="$1"
      _gtr_validate_name "$name" || return 1
      # Optional per-call prefix overrides the default
      local bp="${2:-$prefix}"
      local branch="${bp}${name}"
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
        _gtr_validate_name "$name" || return 1
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
      if [ -z "$1" ]; then
        local main_wt
        main_wt="$(git worktree list --porcelain | sed -n 's/^worktree //p' | head -1)"
        cd "$main_wt" || { echo "gtr: could not find main worktree" >&2; return 1; }
      else
        _gtr_validate_name "$1" || return 1
        cd "$base/$1" || { echo "No such worktree: $base/$1"; return 1; }
      fi
      ;;

    main)
      local main_wt
      main_wt="$(git worktree list --porcelain | sed -n 's/^worktree //p' | head -1)"
      cd "$main_wt" || { echo "gtr: could not find main worktree" >&2; return 1; }
      ;;

    list|ls)
      git worktree list 2>/dev/null || echo "No worktrees found"
      echo ""
      echo "Base path: $base"
      ;;

    claude)
      [ -n "$1" ] || { echo "Usage: gtr claude <name>"; return 1; }
      _gtr_validate_name "$1" || return 1
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
    local base
    base="$(_gtr_base_path)"

    if (( CURRENT == 2 )); then
      _values 'subcommand' create rm cd main list ls claude config version help
    elif (( CURRENT >= 3 )); then
      case "${words[2]}" in
        rm|cd|claude)
          local -a wts
          wts=("$base"/*(/:t))
          compadd -a wts
          ;;
        create)
          if (( CURRENT == 4 )); then
            local -a prefixes
            prefixes=('feat/' 'fix/' 'hotfix/' 'release/')
            compadd -a prefixes
          fi
          ;;
        config)
          _path_files -/
          ;;
      esac
    fi
  }
  compdef _gtr gtr
elif [ -n "$BASH_VERSION" ]; then
  _gtr_bash() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[1]}"
    local base
    base="$(_gtr_base_path)"

    if [ "$COMP_CWORD" -eq 1 ]; then
      COMPREPLY=($(compgen -W "create rm cd main list ls claude config version help" -- "$cur"))
    elif [ "$COMP_CWORD" -ge 2 ]; then
      case "$prev" in
        rm|cd|claude)
          local wts
          if [ -d "$base" ]; then
            wts=$(ls -1 "$base" 2>/dev/null)
          fi
          COMPREPLY=($(compgen -W "$wts" -- "$cur"))
          ;;
        create)
          if [ "$COMP_CWORD" -eq 3 ]; then
            COMPREPLY=($(compgen -W "feat/ fix/ hotfix/ release/" -- "$cur"))
          fi
          ;;
        config)
          COMPREPLY=($(compgen -d -- "$cur"))
          ;;
      esac
    fi
  }
  complete -F _gtr_bash gtr
fi
