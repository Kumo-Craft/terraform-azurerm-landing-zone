###############################################################
# MODULE: KubernetesClusterExtension - Variables
#
# Thin generic wrapper around azurerm_kubernetes_cluster_extension.
# Used to install ARM-managed cluster extensions on AKS clusters:
# Argo CD, Flux, Dapr, Azure App Configuration, etc.
#
# This module does NOT bundle any extension-specific defaults — the
# caller passes `extension_type`, `configuration_settings`, etc. for
# the target extension. Microsoft docs list the per-extension config
# keys (see https://learn.microsoft.com/azure/aks/cluster-extensions).
###############################################################

variable "name" {
  type        = string
  description = "Name of the extension instance on the cluster (e.g. \"argocd\", \"flux\")."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.name))
    error_message = "name must be 1-63 lowercase letters/digits/hyphens, starting with a letter."
  }
}

variable "cluster_id" {
  type        = string
  description = "Full resource ID of the target AKS cluster. For Arc-enabled clusters (Microsoft.Kubernetes/connectedClusters), use the sibling azurerm_arc_kubernetes_cluster_extension resource instead — this module only supports Azure-managed AKS (Microsoft.ContainerService/managedClusters)."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.ContainerService/managedClusters/[^/]+$", var.cluster_id))
    error_message = "cluster_id must be a valid AKS resource ID (Microsoft.ContainerService/managedClusters). Arc-enabled clusters (Microsoft.Kubernetes/connectedClusters) are not supported by this module."
  }
}

variable "extension_type" {
  type        = string
  description = <<-EOT
  Extension type (case-sensitive). Examples:
    - "Microsoft.ArgoCD"   (Argo CD GitOps, currently Preview)
    - "microsoft.flux"     (Flux v2 GitOps, GA)
    - "Microsoft.Dapr"     (Dapr runtime)
    - "Microsoft.AzureML.Kubernetes"  (Azure Machine Learning)
  See: https://learn.microsoft.com/azure/aks/cluster-extensions
  EOT
  nullable    = false

  # F-10: Plan-time typo guard. Azure API will reject invalid types at apply
  # time with a clear message, but this catches common prefix mistakes early.
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9.]+$", var.extension_type))
    error_message = "extension_type must start with a letter and contain only letters, digits, and dots (e.g. \"microsoft.flux\", \"microsoft.azureml.kubernetes\")."
  }
}

variable "release_namespace" {
  type        = string
  description = "Namespace to install the extension into (cluster-scoped install). Mutually exclusive with target_namespace."
  default     = null
}

variable "target_namespace" {
  type        = string
  description = "Single namespace to scope the extension to (namespace-scoped install). Mutually exclusive with release_namespace."
  default     = null
}

variable "release_train" {
  type        = string
  description = "Release train: \"Stable\" (default), \"Preview\", or other extension-specific train (e.g. ArgoCD currently uses Preview)."
  default     = null
}

variable "extension_version" {
  type        = string
  description = "Pin a specific extension version (e.g. \"1.0.0-preview\"). Mutually exclusive with release_train. Named extension_version (not version) because version is a reserved name on module blocks."
  default     = null
}

variable "configuration_settings" {
  type        = map(string)
  description = "Public configuration settings forwarded to the extension. Keys vary per extension (see MS docs)."
  default     = {}
  nullable    = false
}

variable "configuration_protected_settings" {
  type        = map(string)
  description = "Sensitive configuration settings (SSH keys, OAuth secrets, etc.). Stored encrypted by Azure. NOTE: azurerm provider 4.75.0 does not mark configuration_protected_settings as sensitive on the resource — values will appear in Terraform state plaintext. Use a secure state backend (Azure Blob with SSE/CMK)."
  default     = {}
  nullable    = false
  sensitive   = true
}

variable "plan" {
  type = object({
    name           = string
    product        = string
    publisher      = string
    promotion_code = optional(string)
    version        = optional(string)
  })
  description = "Marketplace plan, if the extension is a paid Kubernetes app (typically null for first-party Microsoft extensions like Argo CD/Flux)."
  default     = null
}

###############################################################
# RESOURCE LOCK — F-7
###############################################################

variable "lock" {
  description = "Optional management lock on the extension resource. Note: a CanNotDelete lock will BLOCK extension uninstall/upgrade pipelines — use sparingly."
  type = object({
    name = optional(string)
    kind = string
  })
  default  = null
  nullable = true

  validation {
    condition     = var.lock == null || (try(var.lock.kind, null) != null && contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, "")))
    error_message = "lock.kind must be one of: CanNotDelete, ReadOnly."
  }
}

###############################################################
# ROLE ASSIGNMENTS — F-3
###############################################################

variable "role_assignments" {
  description = <<-EOT
  Map of role assignments. Scope defaults to the extension resource if not specified
  (grant access TO the extension). Set scope to an external resource ID (ACR, KV, Storage)
  to grant the extension's MSI access to that resource — use
  module.kce.aks_assigned_identity[0].principal_id as principal_id.

  - `role_definition_id_or_name`             - (Required) The ID or name of the role definition.
  - `principal_id`                           - (Required) The ID of the principal to assign the role to.
  - `scope`                                  - (Optional) Target resource ID. Defaults to the extension resource ID.
  - `principal_type`                         - (Optional) User, Group, ServicePrincipal, ForeignGroup, or Device.
  - `condition`                              - (Optional) ABAC condition expression.
  - `condition_version`                      - (Optional) Condition version ("2.0").
  - `description`                            - (Optional) Description.
  - `skip_service_principal_aad_check`       - (Optional) Skip AAD check for service principals.
  - `delegated_managed_identity_resource_id` - (Optional) Cross-tenant delegated MSI resource ID.
  EOT
  type = map(object({
    role_definition_id_or_name             = string
    principal_id                           = string
    scope                                  = optional(string, null)
    principal_type                         = optional(string, "ServicePrincipal")
    condition                              = optional(string, null)
    condition_version                      = optional(string, null)
    description                            = optional(string, null)
    skip_service_principal_aad_check       = optional(bool, false)
    delegated_managed_identity_resource_id = optional(string, null)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for ra in values(var.role_assignments) : contains(["User", "Group", "ServicePrincipal", "ForeignGroup", "Device"], ra.principal_type)])
    error_message = "Each role_assignments[*].principal_type must be one of User, Group, ServicePrincipal, ForeignGroup, Device."
  }
}
