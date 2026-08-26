# CI/CD — GitHub Actions

The repo's automation, migrated from the retired Azure DevOps pipelines
(`pipelines/` — removed; same behaviour, GitHub-native mechanics).

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| [ci-modules.yml](ci-modules.yml) | every PR · Mon 06:00 UTC · manual | Dynamic matrix: fmt / init / validate / `terraform test` per changed submodule + root (cheap no-op on docs-only PRs). Weekly run validates **everything**. The **CI OK** summary job is the required branch-protection check. |
| [iac-security.yml](iac-security.yml) | PR touching `*.tf` / lint+scan configs · Mon 05:00 UTC · manual | Checkov + Trivy config (advisory, SARIF → Code Scanning + artifacts) + TFLint (advisory). Final **Checkov regression gate**: red only on a finding not in `.checkov.baseline`. |
| [drift-lint.yml](drift-lint.yml) | PR touching the duplicated blocks · manual | `scripts/check-drift.sh` — warns when orchestrator inline copies drift from canonical modules (advisory until `--strict`). |
| [release-please.yml](release-please.yml) | push to `main` | Automated releases from Conventional Commits: opens the **release PR** (SemVer bump + CHANGELOG); merging it creates the tag + GitHub Release and chains the assets build. |
| [release.yml](release.yml) | `v*` tag push · called by Release Please | **Release Assets** — terraform-docs bundle attached to the release (creates the release with git-log notes when a tag is pushed by hand). |
| [terraform-docs.yml](terraform-docs.yml) | push to `main` touching `modules/**/*.tf` · manual | Regenerates every submodule README's inputs/outputs block (`BEGIN_TF_DOCS` markers); opens a `docs/terraform-docs` PR only when something changed. |
| [provider-freshness.yml](provider-freshness.yml) | Mon 06:00 UTC · manual | Advisory report of latest azurerm/azapi/time versions vs pinned `~>` ranges; files an Issue for a new **major** (Renovate won't PR those). |

Dependency PRs themselves come from the **Renovate GitHub App** (see below),
not from a workflow. Auto-filed issues are deduped by exact title + label via
[`scripts/gh-upsert-issue.sh`](../../scripts/gh-upsert-issue.sh) and labeled
`dependency` + `auto-generated`.

## One-time setup

### 1. Branch protection (replaces the ADO "Build Validation" policies)

Applied on `main` via the API (already active):

- required status check: **CI OK** — the [ci-modules.yml](ci-modules.yml)
  summary job. It aggregates detect + all matrix validates + root; skipped
  jobs (docs-only PR) count as success. One stable context instead of the
  dynamic matrix names.
- force pushes and branch deletion blocked; PR conversations must be
  resolved before merge.
- no required reviews (solo maintainer) and admins not enforced — the
  owner can still push/fix directly in a pinch.

Drift Lint and IaC Security stay **advisory** (not required): they are
path-filtered, and a required path-filtered check blocks PRs that don't
touch its paths. Promote the Checkov regression gate to required only
after removing its path filter and once the baseline caveat in
[iac-security.yml](iac-security.yml) proves stable.

### 2. Renovate (replaces the ADO `renovate.yml` pipeline)

Install the free [Renovate GitHub App](https://github.com/apps/renovate) and
select this repo. The committed [`/renovate.json`](../../renovate.json)
applies as-is — PR-only, grouped non-major provider bumps, isolated majors
with 7-day cool-down, never auto-merge.

### 3. Terraform Registry publish (~2 min, once)

The repo is named `terraform-azurerm-landing-zone` and is public — i.e.
registry-eligible. After the **first release exists** (merge the first
release-please PR so a `v0.1.0` tag is created):

1. Sign in at [registry.terraform.io](https://registry.terraform.io) with
   GitHub, authorizing the `Kumo-Craft` org.
2. **Publish → Module** → select `Kumo-Craft/terraform-azurerm-landing-zone`
   → Publish.
3. Done — every future `v*` tag is auto-imported. Consumers switch from
   `git::…?ref=vX.Y.Z` pins to:

   ```hcl
   source  = "Kumo-Craft/landing-zone/azurerm//modules/KeyVault"
   version = "~> 0.1"
   ```

### 4. Release flow notes

- Use **Conventional Commits** on `main` (`feat:`, `fix:`, `feat!:`) —
  release-please derives the SemVer from them (pre-1.0: breaking → minor).
- Bot-opened PRs (release PR, docs PR) get **no CI runs** (GitHub
  anti-recursion). Merge them with the admin override, close/reopen once
  to trigger CI as yourself, or store a fine-grained PAT
  (contents + pull-requests: write) as the `RELEASE_PLEASE_TOKEN` secret.

### 5. Security features (public repo — already wired)

The repo is **public**, so these come free and are already active:

- **Code Scanning** — [iac-security.yml](iac-security.yml) uploads the
  Checkov/Trivy SARIF (`upload-sarif`); findings appear as inline PR
  annotations and in the Security tab.
- **Secret scanning + push protection** — enabled on the repo; pushes
  containing a recognised credential (Azure client secret, PAT, …) are
  blocked at the push.
