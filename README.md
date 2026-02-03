# MicroGit

A Git integration plugin for the [micro](https://micro-editor.github.io/) text editor.

## Features

- **Git status in statusline**: Displays current branch and modification indicator
- **Git gutter indicators**: Visual markers in the gutter showing added and deleted lines
- **Git blame support**: See who modified each line with commit information
- **Git commands**: Execute common git operations directly from micro
- **Smart caching**: Reduces git command overhead with intelligent caching
- **Automatic updates**: Statusline and gutter update after file saves and opens
- **Repository detection**: Automatically finds git repository in parent directories

## Installation

### Method 1: Manual Installation

1. Clone or download this repository
2. Copy the `microgit` folder to your micro plugins directory:

```bash
cp -r microgit ~/.config/micro/plug/
```

3. Restart micro or run `:plugin install microgit` inside micro

### Method 2: Direct Install (if hosted on GitHub)

```bash
micro -plugin install microgit
```

## Usage

### Statusline Information

Once installed, MicroGit automatically displays git information in the statusline:

- `[main]` - Current branch name
- `[main ●]` - Current branch with uncommitted changes

### Gutter Indicators

Visual markers appear in the gutter (left side of the editor) showing line-by-line git changes:

- **`+`** (Cyan/Info) - Lines that were added
- **`-`** (Red/Error) - Lines that were deleted

These indicators update automatically when you:
- Open a file in a git repository
- Save changes to a file
- Run `:gitrefresh` manually

### Git Blame

Find out who modified each line of code:

- **`:gitblame`** - Shows blame information for the current line in the info bar
  - Format: `[hash] author (date time): commit message`
  - Example: `[a1b2c3d4] John Doe (2024-01-15 10:30:00): Fix bug in parser`

- **`:gitblamefile`** - Opens a new buffer showing git blame for the entire file
  - Each line shows: commit hash, author, date, time, and line number
  - Useful for reviewing the history of an entire file

Blame information is cached for 30 seconds to improve performance.

### Available Commands

Run these commands in micro using `Ctrl+E` to open the command prompt:

| Command | Description |
|---------|-------------|
| `gitstatus` | Show detailed git status |
| `gitadd` | Stage the current file |
| `gitaddall` | Stage all changes (`git add .`) |
| `gitcommit <message>` | Commit staged changes with a message |
| `gitdiff` | Show unstaged changes |
| `gitlog` | Show recent commit history (last 20 commits) |
| `gitbranch` | List all branches |
| `gitblame` | Show git blame info for the current line |
| `gitblamefile` | Show git blame for the entire file in a new buffer |
| `gitrefresh` | Manually refresh git gutter indicators |

### Examples

```
# Stage current file
:gitadd

# Stage all changes
:gitaddall

# Commit with message
:gitcommit Initial commit

# View changes
:gitdiff

# Check status
:gitstatus

# View commit history
:gitlog

# List branches
:gitbranch

# Show blame for current line
:gitblame

# Show blame for entire file
:gitblamefile

# Refresh gutter indicators
:gitrefresh
```

## Keybindings (Optional)

You can add custom keybindings for git commands in your `~/.config/micro/bindings.json`:

```json
{
    "Alt-g,Alt-s": "command:gitstatus",
    "Alt-g,Alt-a": "command:gitadd",
    "Alt-g,Alt-c": "command:gitcommit",
    "Alt-g,Alt-d": "command:gitdiff",
    "Alt-g,Alt-l": "command:gitlog",
    "Alt-g,Alt-b": "command:gitblame"
}
```

## How It Works

- **Automatic Detection**: MicroGit automatically detects if you're working in a git repository by searching parent directories
- **Efficient Caching**: Git information is cached (2 seconds for status, 5 seconds for diff, 30 seconds for blame) to minimize overhead
- **Cache Invalidation**: Cache is cleared after file saves to ensure up-to-date information
- **Buffer-Aware**: Works correctly with multiple open buffers in different directories
- **Smart Command Execution**: All git commands are wrapped in `sh -c` for proper shell execution
- **Gutter Integration**: Uses micro's built-in message system (`buffer.NewMessageAtLine`) for displaying git diff markers
- **Blame Parsing**: Uses `git blame --line-porcelain` format for detailed commit information per line

## Requirements

- micro editor >= 2.0.0
- git installed and available in PATH

## Configuration

Currently, MicroGit works out of the box with sensible defaults. Future versions may include customization options for:

- Cache timeout duration
- Statusline format
- Custom git command aliases

## Contributing

Contributions are welcome! Feel free to:

- Report bugs
- Suggest new features
- Submit pull requests

## License

MIT License

## Author

João Rodrigues Panão de Oliveira

Living in Brazil!

Created for the micro editor community.
