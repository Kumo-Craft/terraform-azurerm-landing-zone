# KubernetesClusterExtension

Installs one ARM-managed extension on an Azure-managed AKS cluster using `azurerm_kubernetes_cluster_extension`. The ARM install path (Microsoft.KubernetesConfiguration) handles all extension lifecycle operations — install, upgrade, and uninstall — via the Azure API, without requiring direct cluster connectivity. Supports all `Microsoft.*` first-party extensions as well as community extension types.

## Prerequisites

- An AKS cluster with a `Microsoft.ContainerService/managedClusters` resource ID. Arc-enabled connected clusters (`Microsoft.Kubernetes/connectedClusters`) are **not supported** by this module — use the sibling `azurerm_arc_kubernetes_cluster_extension` resource directly for those.
- The azurerm provider must be configured by the caller (no provider block emitted by this module).
- Required resource providers registered on the subscription: `Microsoft.KubernetesConfiguration`, `Microsoft.Kubernetes`, `Microsoft.ContainerService`.

## Supported extension types

Common first-party extensions (community extensions are also accepted via the `extension_type` string):

| Extension type | Description | Status |
|---|---|---|
| `microsoft.flux` | Flux v2 GitOps | GA |
| `Microsoft.Dapr` | Dapr runtime | GA |
| `Microsoft.AzureML.Kubernetes` | Azure Machine Learning | GA |
| `Microsoft.AzureDefender.Kubernetes` | Microsoft Defender for Containers | GA |
| `Microsoft.openServiceMesh` | Open Service Mesh | GA |
| `Microsoft.PolicyInsights` | Azure Policy add-on | GA |
| `Microsoft.ArgoCD` | Argo CD GitOps | Preview |

See the full catalog: https://learn.microsoft.com/azure/aks/cluster-extensions

## Usage

### Standalone — Flux GitOps install

```hcl
module "kce" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/KubernetesClusterExtension?ref=v0.2.85"

  name           = "flux"
  cluster_id     = "/subscriptions/.../managedClusters/aks-api-prod-gwc-001"
  extension_type = "microsoft.flux"

  configuration_settings = {
    "helm.versions" = "v3"
  }

  lock = { kind = "CanNotDelete" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/KubernetesClusterExtension"
}

inputs = {
  name           = "flux"
  cluster_id     = dependency.aks.outputs.id
  extension_type = "microsoft.flux"
}
```

## State storage caveat

`var.configuration_protected_settings` is declared `sensitive = true` on the variable, which redacts values from Terraform CLI output. However, the azurerm provider 4.75.0 does **not** mark `configuration_protected_settings` as sensitive on the resource itself — values will be stored **plaintext in Terraform state**.

Mitigation: use a secure state backend. Recommended: Azure Blob Storage with server-side encryption (SSE) and optionally a customer-managed key (CMK). Do not store state files on local disk or in unencrypted backends when using protected settings.

## RoleAssignment composition

`var.role_assignments` supports two patterns:

**Grant access TO the extension resource** (uncommon — extensions are rarely access-controlled):

```hcl
role_assignments = {
  reader = {
    role_definition_id_or_name = "Reader"
    principal_id               = "00000000-0000-0000-0000-000000000001"
    # scope omitted → defaults to the extension resource ID
  }
}
```

**Grant the extension's MSI access to an external resource** (common pattern — ACR pull for Azure ML, Key Vault Reader for Dapr secrets):

```hcl
role_assignments = {
  acr_pull = {
    role_definition_id_or_name = "AcrPull"
    principal_id               = module.kce.aks_assigned_identity[0].principal_id
    scope                      = "/subscriptions/.../registries/acrapiprodgwc"
  }
}
```

Use `module.kce.aks_assigned_identity[0].principal_id` to reference the extension's system-assigned MSI as the principal. Note: `aks_assigned_identity` is an empty list for extension types that do not provision a managed identity — check the extension documentation.

## ResourceLock note

A `CanNotDelete` lock on the extension resource **will block extension uninstall and upgrade pipelines** because those operations delete and recreate the extension resource. Use `ReadOnly` or leave `var.lock = null` (the default) for extensions that are frequently updated.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Extension instance name on the cluster (e.g. "flux", "dapr"). | `string` | -- | Yes |
| cluster_id | Full resource ID of the target AKS cluster (managedClusters only). | `string` | -- | Yes |
| extension_type | Extension type string (case-sensitive). See supported types above. | `string` | -- | Yes |
| release_namespace | Namespace for cluster-scoped install. Mutually exclusive with target_namespace. | `string` | `null` | No |
| target_namespace | Namespace for namespace-scoped install. Mutually exclusive with release_namespace. | `string` | `null` | No |
| release_train | Release train: "Stable", "Preview", or extension-specific train. | `string` | `null` | No |
| extension_version | Pin a specific extension version. Mutually exclusive with release_train. | `string` | `null` | No |
| configuration_settings | Public configuration key/value pairs forwarded to the extension. | `map(string)` | `{}` | No |
| configuration_protected_settings | Sensitive configuration (SSH keys, OAuth secrets). See state caveat. | `map(string)` | `{}` | No |
| plan | Marketplace plan for paid Kubernetes apps. Null for first-party extensions. | `object` | `null` | No |
| lock | Optional management lock (`CanNotDelete` / `ReadOnly`). See lock note. | `object` | `null` | No |
| role_assignments | Map of role assignments (dual-scope: extension self or external resource). | `map(object)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | Resource ID of the cluster extension. |
| name | Extension name on the cluster. |
| current_version | Currently installed extension version (read after apply). |
| resource | The complete `azurerm_kubernetes_cluster_extension` resource object. |
| aks_assigned_identity | Extension's system-assigned managed identity (empty list if none). |
| lock_id | Resource lock ID when `var.lock` is set, otherwise null. |
| role_assignment_ids | Map of role assignment IDs keyed by `var.role_assignments` map key. |

## Resources

| Name | Type |
|------|------|
| azurerm_kubernetes_cluster_extension.this | resource |
| module.lock | module |
| module.role_assignments (for_each) | module |
