# ArgoCDBootstrap

Bootstraps an Argo CD repository connection and a root Application CRD in an AKS cluster. Specifically, this module creates two Kubernetes resources: a `kubernetes_secret_v1` holding the Git repository credentials (PAT) labelled so Argo CD auto-discovers it as a repository connection, and a `kubernetes_manifest` for the `argoproj.io/v1alpha1/Application` CRD pointing Argo CD at the platform manifest path. This module does **NOT** install Argo CD itself — it assumes Argo CD is already running in the cluster.

## Pre-conditions

These requirements MUST be satisfied before running `terraform plan` against this module:

1. **Argo CD must be installed** in the target AKS cluster before applying this module. Use the AKS Argo CD add-on, a separate `helm_release` module, or a manual `kubectl apply` — this module does not install Argo CD.

2. **The CRD `argoproj.io/v1alpha1/Application` must exist** in the cluster. The `kubernetes` provider resolves the OpenAPI schema of `kubernetes_manifest` resources at **plan time**, not just apply time. If the CRD is absent when you run `terraform plan`, the plan fails with a schema-not-found error.

3. **The `kubernetes` provider must be configured by the caller.** This module declares `required_providers { kubernetes ~> 3.0 }` but does not configure it. The caller (typically a Terragrunt `generate "provider"` block) must supply a configured `kubernetes` provider pointed at the target AKS cluster.

## Caller wiring example (Terragrunt)

```hcl
# terragrunt.hcl — in the ArgoCDBootstrap stack layer

dependency "aks" {
  config_path = "../Aks"
}

generate "provider_kubernetes" {
  path      = "provider_kubernetes.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "kubernetes" {
      host                   = "${dependency.aks.outputs.kube_admin_host}"
      cluster_ca_certificate = base64decode("${dependency.aks.outputs.kube_admin_cluster_ca_certificate}")
      client_certificate     = base64decode("${dependency.aks.outputs.kube_admin_client_certificate}")
      client_key             = base64decode("${dependency.aks.outputs.kube_admin_client_key}")
    }
  EOF
}

inputs = {
  repo_url               = "https://dev.azure.com/myorg/myproject/_git/platform-manifests"
  repo_pat               = get_env("TF_VAR_REPO_PAT")
  application_path       = "platform"
  application_name       = "platform"
  destination_namespace  = "argocd"
}
```

## PAT scope requirements

| Provider      | Minimum PAT scope                                      |
|---------------|--------------------------------------------------------|
| Azure DevOps  | `Code (Read)`                                          |
| GitHub        | `repo` (private repos) or no scope (public repos)      |
| GitLab        | `read_repository`                                      |

The PAT is stored as a Kubernetes `Opaque` secret in the `argocd` namespace. It is marked `sensitive = true` in Terraform state. There is no Key Vault integration in this module — the caller is responsible for injecting the PAT securely (see PAT injection patterns below).

## PAT injection patterns

**Option 1 — Terragrunt pipeline env var (recommended for CI/CD)**

Set `TF_VAR_repo_pat` in the pipeline environment. Terragrunt automatically maps `TF_VAR_*` to Terraform variable inputs:

```hcl
# In CI/CD pipeline definition (Azure DevOps, GitHub Actions, etc.)
# Set TF_VAR_repo_pat as a secret variable. Terragrunt picks it up automatically.
inputs = {
  repo_pat = get_env("TF_VAR_repo_pat", "")
}
```

**Option 2 — Key Vault secret in the caller's Terragrunt config**

Read the PAT from Azure Key Vault in the parent Terragrunt config and pass it as an input. This keeps the module provider-free for `azurerm` (avoiding a second provider in the bootstrap layer):

```hcl
# In the parent terragrunt.hcl (where azurerm provider is already configured)
data_source "azurerm_key_vault_secret" "repo_pat" {
  name         = "argocd-repo-pat"
  key_vault_id = dependency.keyvault.outputs.id
}

inputs = {
  repo_pat = data_source.azurerm_key_vault_secret.repo_pat.value
}
```

**Future enhancement (not in this version):** An optional `var.repo_pat_kv_secret_id` input with an opt-in `azurerm` provider block for direct KV-backed credential injection inside the module. Not implemented to keep the module single-provider (`kubernetes` only).

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `repo_url` | `string` | required | Full HTTPS URL of the Git repository Argo CD will pull. |
| `repo_pat` | `string` | required | Personal Access Token used to authenticate to the Git repository. Sensitive. |
| `repo_username` | `string` | `"argocd"` | Username paired with the PAT. For Azure DevOps the value is ignored by the server but must be non-empty. |
| `repo_secret_name` | `string` | `"argocd-platform-manifests-repo"` | Name of the Kubernetes Secret holding the repo credentials. |
| `application_name` | `string` | `"platform"` | Name of the Argo CD Application CRD. |
| `application_path` | `string` | `"platform"` | Path inside the Git repository that Argo CD reconciles. |
| `application_target_revision` | `string` | `"HEAD"` | Git revision (branch, tag, or commit SHA) Argo CD watches. |
| `destination_namespace` | `string` | `"argocd"` | Default destination namespace for manifests that omit their own namespace. |
| `argocd_namespace` | `string` | `"argocd"` | Namespace where Argo CD is installed. |
| `argocd_project` | `string` | `"default"` | Argo CD AppProject the Application belongs to. Use a custom AppProject in production for source/destination restrictions. |
| `sync_policy_prune` | `bool` | `true` | Delete cluster resources when removed from Git. |
| `sync_policy_self_heal` | `bool` | `true` | Revert manual drift back to Git-declared state. |
| `directory_recurse` | `bool` | `true` | Discover manifests recursively under `application_path`. |

## Outputs

| Name | Description | Sensitive |
|------|-------------|-----------|
| `repo_secret_name` | Name of the Kubernetes Secret holding the repo credentials. | false |
| `application_name` | Name of the Argo CD Application CRD. | false |
| `application_repo_url` | Repo URL the Application watches. | false |
| `application_path` | Path inside the repo that the Application reconciles. | false |
| `resource` | The `kubernetes_secret_v1` resource (contains PAT data). | **true** |
| `application` | The `kubernetes_manifest` resource for the Application CRD. | false |

## Resources

| Resource | Description |
|----------|-------------|
| `kubernetes_secret_v1.repo` | Kubernetes Secret in the Argo CD namespace carrying the Git repo URL, username, and PAT. Labelled `argocd.argoproj.io/secret-type: repository` for auto-discovery by Argo CD. |
| `kubernetes_manifest.application` | Argo CD `Application` CRD (`argoproj.io/v1alpha1`) pointing at the configured repo path with automated sync, prune, and self-heal policies. |
