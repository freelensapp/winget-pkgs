# Agent Guide: Freelens WinGet Package

## Overview

This repository maintains the [WinGet](https://github.com/microsoft/winget-cli)
package manifests for [Freelens](https://freelens.app), a FOSS Kubernetes IDE.

It is a fork of [`microsoft/winget-pkgs`](https://github.com/microsoft/winget-pkgs)
that automates manifest generation and submits pull requests to the upstream
repository.

- **`template/`** — Jinja-less YAML templates with placeholder values (`1.2.3`
  as version, dummy SHA256 hashes). These are the *source of truth* for the
  manifest structure.
- **`make.sh`** — The generator script. Reads `.versions.yaml` for the target
  version, queries the GitHub Releases API for real URLs and checksums, then
  uses `yq` to substitute values into the templates.
- **`.versions.yaml`** — Single key `freelens:` with the current target
  version. Managed by Renovate.
- **`renovate.json`** — Renovate configuration that watches the upstream
  `freelensapp/freelens` GitHub releases and opens PRs on the `updates`
  branch.
- **`.github/workflows/winget-update.yaml`** — CI workflow that runs on
  push to `updates` and generates manifests + opens a PR to upstream.

## Target Audience

The CI pipeline runs on **Linux** (`ubuntu-24.04-arm`), but the **consumers**
of the generated manifests are **Windows users** who install Freelens via
`winget install Freelensapp.Freelens`. Always keep both contexts in mind:

- Shell scripts (`make.sh`) target `bash` on Linux — use POSIX-compatible
  constructs, GNU coreutils, and avoid Windows-isms (no `\` line continuations
  in paths, no PowerShell).
- Generated YAML manifests target the
  [WinGet manifest schema](https://github.com/microsoft/winget-cli/tree/master/schemas) —
  paths use Windows conventions (`%ProgramFiles%`, `%LocalAppData%`),
  installer types are Windows-specific (`nullsoft`), and architectures are
  `x64` / `arm64`.

## Security

Never read, display, reference, or include the contents of the following
files in any response or context, even if they are open in the editor:

- `.env`
- `.env.*`
- `*.jks`
- `*.keystore`
- `*.p12`
- `*.pfx`
- `*.pem`
- `*.key`

Never expose secrets (`GH_TOKEN`, etc.) in logs, comments, or generated
output.

## Project Structure

```text
.
├── .github/workflows/winget-update.yaml   # CI pipeline
├── .versions.yaml                          # Current Freelens version
├── make.sh                                 # Manifest generator
├── renovate.json                           # Renovate bot config
├── template/
│   ├── Freelensapp.Freelens.installer.yaml # Installer manifest template
│   ├── Freelensapp.Freelens.locale.en-US.yaml # Default locale template
│   ├── Freelensapp.Freelens.yaml           # Version manifest template
│   └── .yamlfmt.yaml                       # yamlfmt config for generated files
└── manifests/f/Freelensapp/Freelens/       # Generated manifests (one dir per version)
```

## WinGet Manifest Model

Each WinGet package version requires exactly **3 manifest files**:

| File                                      | Manifest Type   | Purpose                                                        |
|-------------------------------------------|-----------------|----------------------------------------------------------------|
| `Freelensapp.Freelens.yaml`               | `version`       | Registers the version number and default locale                |
| `Freelensapp.Freelens.installer.yaml`     | `installer`     | Download URLs, SHA256 hashes, install switches per arch/scope  |
| `Freelensapp.Freelens.locale.en-US.yaml`  | `defaultLocale` | Package metadata, description, release notes                   |

### Installer Matrix

The installer manifest covers 4 combinations:

| Architecture | Scope   | Elevation          | Install Location                   |
|--------------|---------|--------------------|------------------------------------|
| x64          | machine | elevationRequired  | `%ProgramFiles%\Freelens`          |
| x64          | user    | —                  | `%LocalAppData%\Programs\Freelens` |
| arm64        | machine | elevationRequired  | `%ProgramFiles(x86)%\Freelens`     |
| arm64        | user    | —                  | `%LocalAppData%\Programs\Freelens` |

Installer type is `nullsoft` (NSIS) with switches:
- `--updated` for upgrades
- `/allusers` for machine scope
- `/currentuser` for user scope

Schema version: `1.10.0` (tracked in template YAML `$schema` comments).

## How `make.sh` Works

```bash
# 1. Read version from .versions.yaml
version=$(yq -r .freelens .versions.yaml)

# 2. Query GitHub Releases API for the tag v${version}
#    Extracts: releaseDate, releaseUrl, installer URLs, SHA256 URLs

# 3. Download SHA256 files via curl and extract the hash

# 4. Use yq to substitute values into template files:
#    - PackageVersion → ${version}
#    - ReleaseDate → ${releaseDate}
#    - InstallerUrl / InstallerSha256 → real values per architecture
#    - ReleaseNotes → release body from GitHub
#    - ReleaseNotesUrl → release URL

# 5. Write output to manifests/f/Freelensapp/Freelens/${version}/

# 6. Format with yamlfmt using template/.yamlfmt.yaml config
```

### Key Tools

| Tool                   | Purpose                                                              |
|------------------------|----------------------------------------------------------------------|
| `yq` (mikefarah/yq)    | YAML processing, template variable substitution                      |
| `gh` (GitHub CLI)      | Query GitHub Releases API, create PRs                                |
| `curl`                 | Download SHA256 checksum files                                       |
| `yamlfmt`              | Consistent YAML formatting of generated manifests                    |
| `mise`                 | Runtime version manager (used in CI to install yq, gh, etc.)         |

### Template Convention

Templates use `1.2.3` as a sentinel version and `AAAA...` (64 `A` characters)
as a sentinel SHA256. All real values are injected by `make.sh` via `yq`
expressions. The templates are **not** Jinja/Go templates — they are valid
standalone YAML files that `yq` reads and transforms.

## CI Workflow (`winget-update.yaml`)

### Triggers

- Push to `updates` branch (when `.versions.yaml`, `make.sh`, `template/**`,
  or the workflow itself changes)
- Issue comment `/rerun` on this repository
- Manual `workflow_dispatch`

### Runner

`ubuntu-24.04-arm` — the only supported runner. All tooling must be available
on this platform.

### Flow

1. Checkout `master` and reset to `upstream/master` (microsoft/winget-pkgs)
2. Checkout `updates` branch into `updates.tmp/` subdirectory
3. Install tools via mise
4. Run `make.sh` to generate manifests
5. Commit changes if any, push to a new branch `Freelensapp-Freelens-${version}`
6. Create PR to `microsoft/winget-pkgs:master`

### Remote Layout

- `origin` → `freelensapp/winget-pkgs` (our fork)
- `upstream` → `microsoft/winget-pkgs` (canonical repo)

PRs are always opened against `microsoft/winget-pkgs:master` from
`freelensapp:Freelensapp-Freelens-${version}`.

## Branch Conventions

- **`master`** — Mirrors `microsoft/winget-pkgs:master`. Never commit
  directly; always reset from upstream.
- **`updates`** — Our working branch where Renovate opens version bump PRs.
  Manifests are generated from this branch.
- **`Freelensapp-Freelens-${version}`** — Auto-generated branches for each
  version PR to upstream.

## Renovate Configuration

Renovate watches `freelensapp/freelens` GitHub releases via a custom regex
manager in `.versions.yaml`:

```yaml
freelens: 1.10.0 # datasource=github-releases depName=freelensapp/freelens
```

When a new release is detected, Renovate opens a PR against the `updates`
branch bumping the version. Merging that PR triggers the CI workflow.

Key settings:
- `semanticCommitsDisabled: true` — no conventional commit prefixes
- `forkProcessing: enabled` — works on forked repositories
- ASDF plugin manager is disabled (`matchManagers: ["asdf"] → enabled: false`)
  because this repo doesn't use `.tool-versions` for tool installation

## Common Tasks

### Adding Support for a New Architecture

1. Add new installer entries to `template/Freelensapp.Freelens.installer.yaml`
   following the existing pattern (x64/arm64, machine/user scope pairs)
2. Update `make.sh` to fetch the new architecture's installer URL and SHA256
3. Add the corresponding `yq` substitution expressions in `make.sh`

### Updating Manifest Schema Version

1. Update `$schema` URLs in all 3 template files
2. Update `ManifestVersion` field values
3. Check the WinGet schema changelog for breaking changes

### Testing `make.sh` Locally

```bash
# Set a test version
echo "freelens: 1.10.0" > .versions.yaml

# Run the generator (needs gh auth and curl)
bash make.sh

# Check output
ls manifests/f/Freelensapp/Freelens/1.10.0/
```

### Validating Generated Manifests

Use the WinGet CLI on Windows to validate:
```powershell
winget validate --manifest manifests/f/Freelensapp/Freelens/1.10.0/
```

## Best Practices

1. **Templates are the source of truth** — always update templates first,
   then regenerate. Never edit generated manifests directly.
2. **Keep `make.sh` idempotent** — running it twice with the same inputs
   should produce identical output.
3. **Follow WinGet schema** — refer to
   [winget-cli schemas](https://github.com/microsoft/winget-cli/tree/master/schemas/JSON)
   when modifying templates.
4. **Use `yq` not `sed`** for YAML transformations. YAML is structured data;
   regex-based substitution is fragile.
5. **Preserve cross-platform awareness** — scripts run on Linux but produce
   Windows manifests. File paths, line endings (LF in repo, CRLF never used),
   and environment variable syntax must respect both.
6. **Format generated YAML** — always run `yamlfmt` as the final step.
7. **Do not use Anthropic Fable for coding tasks** — Fable may be used only
   for planning, analysis, and thinking through problems. When writing or
   editing code, use standard editing tools.

## Validation Before Commit

For shell scripts and YAML files, run:

```bash
# Lint shell scripts
shellcheck make.sh

# Validate YAML syntax for templates
yq eval '.' template/*.yaml

# Validate YAML syntax for generated manifests (if present)
yq eval '.' manifests/f/Freelensapp/Freelens/*/*.yaml 2>/dev/null || true
```

## GitHub Actions (Claude Code Action) Rules

When operating via the `claude.yaml` workflow (i.e., invoked from a PR
comment, issue, or review), follow these rules.

### Code Review

When reviewing code and proposing fixes:

1. **Show the diff first** — present every proposed change as a unified diff
   block using the `diff` language tag:

   ```diff
   --- a/template/Freelensapp.Freelens.installer.yaml
   +++ b/template/Freelensapp.Freelens.installer.yaml
   @@ -10,7 +10,7 @@
    InstallerSwitches:
   -  Upgrade: --updated
   +  Upgrade: --update
    UpgradeBehavior: install
   ```

   Generate with: `git diff -u -- path/to/file`

   If the change spans multiple files, group them under a single commit
   subject and show each file's diff sequentially.

2. **Propose a commit subject first** — before any code change, output a
   single line with the proposed commit subject:

   ```text
   **Proposed commit:** <short description>
   ```

   Do **not** use Conventional Commits prefixes (e.g. `fix:`, `feat:`,
   `chore:`, `refactor:`, `docs:`, `test:`, `ci:`). This project prefers
   plain, descriptive commit messages and PR titles without any prefix.

   Wait for the user to confirm (or adjust) the subject before applying the
   change.

3. **Comment style:**
   - Keep review comments concise and actionable
   - Reference specific lines (file + line number) when pointing out issues
   - Offer a concrete fix suggestion rather than just flagging a problem
   - Do **not** use emoji in any Markdown, comments, commit messages, or
     PR descriptions. The only exception is emoji that already appears
     inside code strings (e.g. application logs, user-facing messages).
   - Use GitHub's `suggestion` block for small targeted fixes:

     ````suggestion
     <same unified-diff format as shown above>
     ````

   - For larger multi-file changes, use `diff -u` blocks in a regular
     comment instead, with the proposed commit subject shown first

### Making Changes to a PR

When asked to implement a change on a PR:

1. Propose the commit subject (as above)
2. Describe what will change and why
3. After confirmation, apply the changes with commits on the PR branch
4. **One commit per fix** — when a review surfaces more than one issue or
   the plan includes more than one fix, apply and commit each fix
   separately. Do not batch multiple independent fixes into a single
   commit.

### Modifying GitHub Actions Workflows

Claude cannot push changes to files under `.github/workflows/` directly,
because the GitHub token used by the action lacks the `workflows` permission.
Any patch to a workflow file MUST therefore be delivered as a new, complete
file under the `github-workflow-fix/` directory instead:

1. Write the full, final contents of the workflow to
   `github-workflow-fix/<workflow-file-name>`.
2. Make it a **complete** file — the entire workflow as it should look after
   the change, not just a diff or fragment.
3. Commit and open the PR as usual. In the PR description, clearly note that
   the file is a proposed workflow change and that a maintainer must move it
   from `github-workflow-fix/` to `.github/workflows/` manually.

### Branch Naming Conventions

When creating a branch from an issue, use a human-readable name:

```text
claude/issue-<number>-<short-slug>
```

- `<number>` is the GitHub issue number
- `<short-slug>` is a kebab-case summary (3–6 words, omit articles)

Do **not** use auto-generated timestamp suffixes.

### PR Title Conventions

- **Agent-related changes** — PRs changing `AGENTS.md`, `CLAUDE.md`,
  `.github/workflows/claude.yaml`, or other agent governance files MUST
  use the prefix `Claude:`.

  Examples:
  - `Claude: Add WinGet manifest structure documentation`
  - `Claude: Update claude.yaml workflow permissions`

- **All other PRs** — use plain, descriptive titles without any prefix.

### Pushing Changes from Fork PRs

When commits cannot be pushed to a fork PR:

1. Create a new branch on `freelensapp/winget-pkgs`:
   ```bash
   git checkout -b claude/<original-branch-name>
   git push --force-with-lease upstream claude/<original-branch-name>
   ```
   (`upstream` here is `freelensapp/winget-pkgs`, not `microsoft/winget-pkgs`)

2. Open a new PR with the **exact same title** as the original. Reference
   the original PR in the description.

3. Post a comment on the original PR with a link to the new PR and close it.

### Closing PRs

Claude may only close a PR when ALL of the following are true:

1. The PR was created by Claude from a `claude/` branch, OR the PR is the
   original fork PR that Claude's `claude/` branch supersedes.
2. The close reason is explicitly explained in a comment on the PR.

### Model Information in Comments

When operating via the GitHub Actions workflow, include the model ID in the
footer of every GitHub comment and PR description:

```text
[View job run](...) | Model: `claude-sonnet-4-6`
```

### Development Environment

The GitHub Actions runner is `ubuntu-24.04-arm` with shell tools available.
The following CLI tools are explicitly allowed:

- `gh` (all subcommands) — for managing pull requests and releases
- `yq` (mikefarah/yq) — for YAML processing
- `git` (all subcommands) — for viewing changes, creating branches,
  committing, and pushing
- `curl` — for downloading artifacts
- `bash` — for running `make.sh` and inline scripts
- `grep`, `find`, `xargs` — for searching and iterating
- `sed`, `awk`, `cut`, `tr` — for text transformation
- `sort`, `uniq` — for list processing
- `cat`, `head`, `tail`, `wc` — for viewing and measuring files
- `ls`, `tree` — for listing directory contents
- `mkdir`, `touch`, `cp`, `mv`, `rm` — for file and directory operations
- `tee`, `echo` — for pipeline debugging and scripting

## Getting Help

- [WinGet Manifest Specification](https://github.com/microsoft/winget-cli/tree/master/schemas)
- [WinGet CLI documentation](https://learn.microsoft.com/en-us/windows/package-manager/)
- [mikefarah/yq documentation](https://mikefarah.gitbook.io/yq)
- Check existing manifests in `manifests/f/Freelensapp/Freelens/` for patterns
- Review the CI workflow history for past update behavior
