# gtr

A shell function for managing git worktrees and Claude Code sessions with a simple, ergonomic interface.

`gtr` wraps `git worktree` to make creating, switching, and cleaning up worktrees fast and painless. It automatically names branches, copies gitignored config directories (`.claude`, `.prompts`) into new worktrees, and lets you launch [Claude Code](https://claude.ai/claude-code) sessions directly inside any worktree.

## Installation

### Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/proofofze/gtr/master/install.sh | bash
```

This downloads `gtr.sh` to `~/.gtr/`, adds a source line to your `~/.zshrc` or `~/.bashrc`, and sets up tab completion. Restart your shell or run `source ~/.zshrc` to start using it.

To install to a custom directory:

```bash
GTR_INSTALL_DIR="$HOME/.local/share/gtr" curl -fsSL https://raw.githubusercontent.com/proofofze/gtr/master/install.sh | bash
```

### Manual install

```bash
# Clone the repository
git clone https://github.com/proofofze/gtr.git

# Or just grab the script
curl -o gtr.sh https://raw.githubusercontent.com/proofofze/gtr/master/gtr.sh
```

Then add to your `~/.zshrc` or `~/.bashrc`:

```bash
source /path/to/gtr.sh
```

Tab completion is set up automatically for both zsh and bash.

## Usage

```
gtr <command> [options] [name ...]
```

### Commands

| Command | Description |
|---|---|
| `gtr create <name> [...]` | Create one or more worktrees with auto-prefixed branches |
| `gtr rm [-f] <name> [...]` | Remove worktree(s) and their branches |
| `gtr cd <name>` | Change directory into a worktree |
| `gtr list` | List all worktrees |
| `gtr claude <name>` | Open Claude Code inside a worktree (creates it if needed) |
| `gtr version` | Show version |
| `gtr help` | Show help |

### Examples

```bash
# Create a worktree — branch "feat/login-page" is created automatically
gtr create login-page

# Create multiple worktrees at once
gtr create auth dashboard settings

# Jump into a worktree
gtr cd login-page

# Remove a worktree and its branch
gtr rm login-page

# Force-remove a worktree with uncommitted changes
gtr rm -f login-page

# Launch Claude Code in a worktree (creates it if it doesn't exist)
gtr claude login-page

# Use a custom branch prefix
GTR_BRANCH_PREFIX=fix/ gtr create bug-42   # branch: fix/bug-42
```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `GTR_WORKTREE_DIR` | `~/code/worktrees` | Base directory where worktrees are created |
| `GTR_BRANCH_PREFIX` | `feat/` | Prefix for new branch names |

Set these in your shell profile to customize:

```bash
export GTR_WORKTREE_DIR="$HOME/worktrees"
export GTR_BRANCH_PREFIX="wt/"
```

## Features

- **Automatic branch naming** — `gtr create foo` creates branch `feat/foo` (configurable prefix).
- **Existing branch detection** — If the branch already exists, it checks it out instead of failing.
- **Config directory copying** — Copies `.claude` and `.prompts` directories into new worktrees when they are gitignored in the source repo.
- **Claude Code integration** — `gtr claude <name>` opens Claude Code directly in the worktree.
- **Tab completion** — Works out of the box in both zsh and bash.

## License

MIT
