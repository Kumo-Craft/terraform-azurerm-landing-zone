# CI/CD — GitHub Actions

The repo's automation, migrated from the retired Azure DevOps pipelines
(`pipelines/` — removed; same behaviour, GitHub-native mechanics).

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| [ci-modules.yml](ci-modules.yml) | PR touching `*.tf` / tests · Mon 06:00 UTC · manual | Dynamic matrix: fmt / init / validate / `terraform test` per changed submodule + root. Weekly run validates **everything**. |
| [iac-security.yml](iac-security.yml) | PR touching `*.tf` / lint+scan configs · Mon 05:00 UTC · manual | Checkov + Trivy config (advisory, SARIF → Code Scanning + artifacts) + TFLint (advisory). Final **Checkov regression gate**: red only on a finding not in `.checkov.baseline`. |
| [drift-lint.yml](drift-lint.yml) | PR touching the duplicated blocks · manual | `scripts/check-drift.sh` — warns when orchestrator inline copies drift from canonical modules (advisory until `--strict`). |
| [release.yml](release.yml) | `v*` tag push | terraform-docs bundle + git-log release notes, published as a **GitHub Release**. |
| [provider-freshness.yml](provider-freshness.yml) | Mon 06:00 UTC · manual | Advisory report of latest azurerm/azapi/time versions vs pinned `~>` ranges; files an Issue for a new **major** (Renovate won't PR those). |

Dependency PRs themselves come from the **Renovate GitHub App** (see below),
not from a workflow. Auto-filed issues are deduped by exact title + label via
[`scripts/gh-upsert-issue.sh`](../../scripts/gh-upsert-issue.sh) and labeled
`dependency` + `auto-generated`.

## One-time setup

### 1. Branch protection (replaces the ADO "Build Validation" policies)

Settings → Branches → protection rule on `main` → require status checks:

- `Detect modified modules`, `Validate submodule`, `Validate root meta-module` (CI Modules)
- `Run drift check` — keep **optional** (advisory) like on ADO
- `Checkov + Trivy — IaC posture (modules/)` — keep **optional** until the
  baseline-keyed regression gate proves stable (see the caveat in
  [iac-security.yml](iac-security.yml)), then make it required

### 2. Renovate (replaces the ADO `renovate.yml` pipeline)

Install the free [Renovate GitHub App](https://github.com/apps/renovate) and
select this repo. The committed [`/renovate.json`](../../renovate.json)
applies as-is — PR-only, grouped non-major provider bumps, isolated majors
with 7-day cool-down, never auto-merge.

### 3. Security features (public repo — already wired)

The repo is **public**, so these come free and are already active:

- **Code Scanning** — [iac-security.yml](iac-security.yml) uploads the
  Checkov/Trivy SARIF (`upload-sarif`); findings appear as inline PR
  annotations and in the Security tab.
- **Secret scanning + push protection** — enabled on the repo; pushes
  containing a recognised credential (Azure client secret, PAT, …) are
  blocked at the push.
