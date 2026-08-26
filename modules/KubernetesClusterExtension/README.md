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

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | ~> 4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| lock | ../ResourceLock | n/a |
| role\_assignments | ../RoleAssignment | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_kubernetes_cluster_extension.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_extension) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster\_id | Full resource ID of the target AKS cluster. For Arc-enabled clusters (Microsoft.Kubernetes/connectedClusters), use the sibling azurerm\_arc\_kubernetes\_cluster\_extension resource instead — this module only supports Azure-managed AKS (Microsoft.ContainerService/managedClusters). | `string` | n/a | yes |
| extension\_type | Extension type (case-sensitive). Examples:<br>  - "Microsoft.ArgoCD"   (Argo CD GitOps, currently Preview)<br>  - "microsoft.flux"     (Flux v2 GitOps, GA)<br>  - "Microsoft.Dapr"     (Dapr runtime)<br>  - "Microsoft.AzureML.Kubernetes"  (Azure Machine Learning)<br>See: https://learn.microsoft.com/azure/aks/cluster-extensions | `string` | n/a | yes |
| name | Name of the extension instance on the cluster (e.g. "argocd", "flux"). | `string` | n/a | yes |
| configuration\_protected\_settings | Sensitive configuration settings (SSH keys, OAuth secrets, etc.). Stored encrypted by Azure. NOTE: azurerm provider 4.75.0 does not mark configuration\_protected\_settings as sensitive on the resource — values will appear in Terraform state plaintext. Use a secure state backend (Azure Blob with SSE/CMK). | `map(string)` | `{}` | no |
| configuration\_settings | Public configuration settings forwarded to the extension. Keys vary per extension (see MS docs). | `map(string)` | `{}` | no |
| extension\_version | Pin a specific extension version (e.g. "1.0.0-preview"). Mutually exclusive with release\_train. Named extension\_version (not version) because version is a reserved name on module blocks. | `string` | `null` | no |
| lock | Optional management lock on the extension resource. Note: a CanNotDelete lock will BLOCK extension uninstall/upgrade pipelines — use sparingly. | <pre>object({<br>    name = optional(string)<br>    kind = string<br>  })</pre> | `null` | no |
| plan | Marketplace plan, if the extension is a paid Kubernetes app (typically null for first-party Microsoft extensions like Argo CD/Flux). | <pre>object({<br>    name           = string<br>    product        = string<br>    publisher      = string<br>    promotion_code = optional(string)<br>    version        = optional(string)<br>  })</pre> | `null` | no |
| release\_namespace | Namespace to install the extension into (cluster-scoped install). Mutually exclusive with target\_namespace. | `string` | `null` | no |
| release\_train | Release train: "Stable" (default), "Preview", or other extension-specific train (e.g. ArgoCD currently uses Preview). | `string` | `null` | no |
| role\_assignments | Map of role assignments. Scope defaults to the extension resource if not specified<br>(grant access TO the extension). Set scope to an external resource ID (ACR, KV, Storage)<br>to grant the extension's MSI access to that resource — use<br>module.kce.aks\_assigned\_identity[0].principal\_id as principal\_id.<br><br>- `role_definition_id_or_name`             - (Required) The ID or name of the role definition.<br>- `principal_id`                           - (Required) The ID of the principal to assign the role to.<br>- `scope`                                  - (Optional) Target resource ID. Defaults to the extension resource ID.<br>- `principal_type`                         - (Optional) User, Group, ServicePrincipal, ForeignGroup, or Device.<br>- `condition`                              - (Optional) ABAC condition expression.<br>- `condition_version`                      - (Optional) Condition version ("2.0").<br>- `description`                            - (Optional) Description.<br>- `skip_service_principal_aad_check`       - (Optional) Skip AAD check for service principals.<br>- `delegated_managed_identity_resource_id` - (Optional) Cross-tenant delegated MSI resource ID. | <pre>map(object({<br>    role_definition_id_or_name             = string<br>    principal_id                           = string<br>    scope                                  = optional(string, null)<br>    principal_type                         = optional(string, "ServicePrincipal")<br>    condition                              = optional(string, null)<br>    condition_version                      = optional(string, null)<br>    description                            = optional(string, null)<br>    skip_service_principal_aad_check       = optional(bool, false)<br>    delegated_managed_identity_resource_id = optional(string, null)<br>  }))</pre> | `{}` | no |
| target\_namespace | Single namespace to scope the extension to (namespace-scoped install). Mutually exclusive with release\_namespace. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| aks\_assigned\_identity | Extension's system-assigned managed identity (principal\_id, tenant\_id, type). Empty list if no identity assigned by Azure (depends on extension type). |
| current\_version | Currently installed extension version (read after apply). |
| id | Resource ID of the cluster extension. |
| lock\_id | Resource lock ID when var.lock is set, otherwise null. |
| name | Extension name on the cluster. |
| resource | The azurerm\_kubernetes\_cluster\_extension resource. |
| role\_assignment\_ids | Map of role assignment IDs keyed by the var.role\_assignments map key. |
<!-- END_TF_DOCS -->
