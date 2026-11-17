# Contributing

Thanks for helping improve this status line. Bug reports, new segments and fixes are all welcome.

## Before you start

For anything bigger than a small fix, open an issue first so we can agree on the approach before you write
the code.

## Testing your changes

The script reads Claude Code's JSON from standard input, so you can run it directly without restarting
Claude Code:

```sh
echo '{"model":{"display_name":"Opus 5.5"},"effort":{"level":"high"},"context_window":{"used_percentage":42}}' \
  | bash statusline.sh
```

To test with real data, capture the JSON that Claude Code sends by changing the command in
`~/.claude/settings.json` for a moment:

```json
"command": "tee /tmp/statusline-input.json | bash ~/.claude/statusline.sh"
```

Then replay it with `bash statusline.sh < /tmp/statusline-input.json`. The file contains your paths and
session name, so review it before sharing it anywhere.

Check at least these cases:

- Full input, with every field your change touches.
- Empty input: `echo '{}' | bash statusline.sh` must print nothing and exit without errors.
- Partial input, where the fields your segment uses are missing.

The field reference is in the [official status line documentation](https://code.claude.com/docs/en/statusline).

## Linting

Run [ShellCheck](https://www.shellcheck.net/) before opening a pull request:

```sh
shellcheck statusline.sh install.sh
```

There is no CI on this repository, so this check is up to you and to the reviewer.

## Guidelines

- **Dependencies**: only `bash`, `jq`, `git` and `date`. Anything else needs a strong reason, discussed in an
  issue first.
- **Missing data**: a segment prints nothing when Claude Code does not send its data. Many fields depend on
  the plan, the Claude Code version or the moment in the session.
- **Numbers**: round decimals in the `jq` block at the top of the script, not in the shell. Shell
  arithmetic is integer only, and `printf '%.0f'` fails in locales that use a comma as decimal separator.
- **Dates**: format them with `fmt_time`, which works with both GNU and BSD `date` and keeps month names
  in English.
- **Speed**: Claude Code runs the script on every update. Avoid network calls and slow commands.
- **Portability**: if you can, test on both Linux and macOS, and say in the pull request where you tested.

## Pull requests

- Keep each pull request focused on one change.
- For visual changes, include a before and after screenshot.
- Fill in the pull request template.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
