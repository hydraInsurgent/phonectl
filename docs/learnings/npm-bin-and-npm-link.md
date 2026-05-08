---
title: 'npm `bin` and `npm link`: How a Script Becomes a Global Command'
category: packaging
tags: [npm, packaging, cli, global-install, node, path, dev-loop]
related: []
first_encountered: PhoneCTL v0.1
created: 2026-05-07
updated: 2026-05-07
---

# npm `bin` and `npm link`: How a Script Becomes a Global Command

When you `npm install -g phonectl` and `phonectl --help` works in any directory, several pieces of plumbing meet: `package.json`'s `bin` field, npm's global prefix, and your shell's `$PATH`. Understanding the chain matters because development uses a slightly different chain (`npm link`), and "why isn't `phonectl` on my PATH" debugging requires knowing each link.

## Mental model

`package.json` declares an entrypoint:

```json
{
  "name": "phonectl",
  "bin": { "phonectl": "./bin/phonectl" }
}
```

When the package is installed globally, npm:

1. Places the package files in `<global-prefix>/lib/node_modules/phonectl/`
2. Creates a symlink at `<global-prefix>/bin/phonectl` pointing to that package's `bin/phonectl`
3. Marks the symlink target executable (`chmod +x`)

The user's shell finds `<global-prefix>/bin/` on `$PATH` (npm-managed installs put it there automatically; some setups need manual PATH wiring). Running `phonectl` follows the symlink, executes the script.

`npm link` is the same chain in reverse: instead of installing from a tarball, it symlinks `<global-prefix>/lib/node_modules/phonectl/` to your *working repo*. Edit-and-rerun development without `npm publish` round-trips.

```
~/repos/phonectl/                  ─── source of truth (your repo)
├── bin/phonectl                   ─── executable script
└── package.json (bin entry)

  npm link symlinks the package itself:
  <prefix>/lib/node_modules/phonectl  ──►  ~/repos/phonectl

  And the bin symlink:
  <prefix>/bin/phonectl  ──►  <prefix>/lib/node_modules/phonectl/bin/phonectl

  Which because of the first symlink resolves transitively to:
  <prefix>/bin/phonectl  ──►  ~/repos/phonectl/bin/phonectl
```

Edit `bin/phonectl` in your repo, the next `phonectl ...` invocation runs the new code. No rebuild, no reinstall.

## Why this exists

Pre-npm CLI distribution looked like:

- "Download this tarball, copy `bin/foo` into `/usr/local/bin/`, `chmod +x`."

That's a four-step manual install per machine, with platform-specific path conventions, and an upgrade story that means re-downloading and re-copying. npm's global install consolidates that into one command for any node-using developer:

```
npm install -g foo
```

The `bin` field declaratively says "this package contributes one or more global commands"; npm handles the symlinking and the chmod. The same convention works on Linux, macOS, and Windows (where npm creates `.cmd` shims instead of symlinks because Windows shells need them).

`npm link` exists because publishing a new version every time you want to test a tiny change is slow and pollutes the version history. With `npm link`, your shell sees the in-development code as if it were globally installed.

## How it actually works

### The bin field

Two shapes:

```json
"bin": "./bin/foo"            // implies the command name == package name
"bin": {                      // explicit map; multiple commands allowed
  "foo": "./bin/foo",
  "foo-extras": "./bin/foo-extras"
}
```

The script must have a shebang. For bash CLIs:

```bash
#!/usr/bin/env bash
```

For node CLIs:

```js
#!/usr/bin/env node
```

The `#!/usr/bin/env <interpreter>` indirection is portable across systems where the interpreter is at different absolute paths. macOS `bash` is at `/bin/bash`; some Linuxes have it at `/usr/local/bin/bash`; `env` looks up `bash` on the user's PATH.

### Global prefix lookup

```bash
npm config get prefix       # where npm installs global packages
npm prefix -g               # alias of the above
```

On Linux/macOS without setup, this defaults to `/usr/local` (so global installs need sudo). With nvm-managed node, it's typically `~/.nvm/versions/node/<version>/`. Either way, `<prefix>/bin/` is what ends up on PATH.

### Permission bit on the symlinked script

npm calls `chmod +x` on the package's bin script during install. If you're hand-rolling something equivalent to `npm link` (rare), make sure the script has the executable bit. PhoneCTL's `package.json` doesn't add a `postinstall` chmod because npm handles it - but if a test extracts the tarball manually, `chmod +x bin/phonectl` is needed.

### `readlink -f` inside the script

The bin symlink chain means `${BASH_SOURCE[0]}` inside the script is the symlink path (`<prefix>/bin/phonectl`), not the real file. Sourcing sibling files relative to `${BASH_SOURCE[0]}` would look in `<prefix>/bin/`, which doesn't have a `lib/` directory. Resolution: use `readlink -f` (Linux) or `realpath` (macOS, with coreutils, or Linux equivalent) to canonicalise to the real file path before locating siblings:

```bash
PCTL_BIN="$(readlink -f "${BASH_SOURCE[0]}")"
PCTL_ROOT="$(cd "$(dirname "${PCTL_BIN}")/.." && pwd)"
source "${PCTL_ROOT}/lib/core/output.sh"
```

This is the difference between a CLI that works only when run from the source directory and one that works anywhere on PATH.

## Common misconceptions

- **"`npm link` copies the package to global."** No. It creates a symlink. Edits to the source file are visible immediately to subsequent invocations.
- **"Global install needs sudo."** Only when `<prefix>` is owned by root, which is the default on Linux/macOS. nvm-managed node installs `<prefix>` under the user's home directory, so no sudo. Most CI environments and modern dev setups use nvm or a similar version manager.
- **"`bin` works without a shebang as long as it has `#!/usr/bin/env node` somewhere."** It does not. The shebang must be the first two characters of the file. A blank first line breaks it.
- **"`bin` paths are case-insensitive."** They are not on Linux. `"bin": "./bin/Foo"` is a distinct file from `./bin/foo`.
- **"`npm unlink` removes the global symlink."** It does, but the project's local `node_modules/.bin/` symlink (created by `npm link <other-package>`) is a separate thing - confusingly, `npm unlink <other>` from a project removes that local symlink, not the global one.
- **"Node CLIs don't need a Node dependency at install time."** They do. The `bin` script's shebang invokes node; if the user doesn't have node installed, the command fails. Bash bin scripts are simpler in that regard - their dep is bash, which is everywhere.

## When it matters in practice

- **Developing a CLI with the test loop tight.** `npm link` once, then edit-and-rerun. No `npm pack` or `npm publish` cycle.
- **Debugging "command not found" right after `npm install -g`.** The fix is almost always: PATH doesn't include `<global-prefix>/bin/`. Check `npm prefix -g` and verify `$PATH`. nvm users: `nvm use <version>` may not propagate to all shells.
- **Distributing a bash CLI via npm specifically.** PhoneCTL is exactly this case - bash script, ships via npm because that's where Linux/macOS dev users already are. The trick is the shebang (bash, not node) and a script that doesn't depend on node features.
- **Multiple commands from one package.** The `bin` field's object form maps each command name to a script, so a single package can install (e.g.) `phonectl` and `phonectl-init` as two distinct executables.
- **Switching nvm node versions.** Each version has its own global prefix. `npm link`-ed packages disappear when you switch versions; `nvm use 20 && phonectl` may say "not found" while `nvm use 18 && phonectl` works. Not a bug, just a confusion.

## Configuration in common stacks

| Stack | How a script becomes globally available |
|---|---|
| **npm** | `bin` field in package.json + `npm install -g` or `npm link` |
| **pip / Python** | `entry_points` in `setup.py` / `pyproject.toml`, then `pip install -e .` (editable) |
| **cargo / Rust** | `[[bin]]` section in `Cargo.toml`, `cargo install --path .` |
| **Go** | `go install ./cmd/foo` puts the binary in `$GOBIN` |
| **Homebrew formula** | `bin.install` in the formula installs to `<prefix>/bin/` |
| **Manual** | Drop the script into `~/.local/bin/` (Linux convention) or `/usr/local/bin/` (older convention) and `chmod +x` |

For PhoneCTL development specifically, run `npm link` once from the repo root after `npm install`. To uninstall: `npm unlink -g phonectl` from anywhere.

## Further reading

- **npm docs: package.json `bin`** - https://docs.npmjs.com/cli/v10/configuring-npm/package-json#bin
- **npm docs: `npm link`** - https://docs.npmjs.com/cli/v10/commands/npm-link
- **npm docs: `npm config`** - explains `prefix` and how to relocate global installs to user-owned paths to avoid sudo. https://docs.npmjs.com/cli/v10/commands/npm-config
- **Why use `#!/usr/bin/env <interp>`** - the canonical writeup is in `man env` and `man execve`; the short version is "look up the interpreter on PATH at runtime, don't hardcode the install path".
- **`man readlink`** and **`man realpath`** - the canonicalisation tools. `readlink -f` is GNU; `realpath` is also in coreutils. macOS without coreutils needs `realpath` from `brew install coreutils`.
