###############################################################
# CORE
###############################################################
variable "architecture_name" {
  type        = string
  default     = "core"
  nullable    = false
  description = "ALZ architecture name"
}

variable "management_root_id" {
  type        = string
  nullable    = false
  description = "Parent management group ID (tenant root)"
}

variable "location" {
  type        = string
  nullable    = false
  description = "Default Azure region for DINE policy remediation deployments (e.g. AMBA resource group, Log Analytics, DCR). Not a management group resource attribute — management groups are global."
}

###############################################################
# HIERARCHY SETTINGS
###############################################################
variable "management_group_hierarchy_settings" {
  type = object({
    default_management_group_name            = string
    require_authorization_for_group_creation = optional(bool, true)
    update_existing                          = optional(bool, false)
  })
  default     = null
  description = "Tenant-level hierarchy settings. Sets default MG for new subs and restricts MG creation."
}

###############################################################
# SUBSCRIPTIONS
###############################################################
variable "subscription_placement" {
  type = map(object({
    subscription_id       = string
    management_group_name = string
  }))
  nullable    = false
  description = "Map of subscription placements in management groups"
}

variable "management_subscription_id" {
  type        = string
  nullable    = false
  description = "Management subscription ID"
}

variable "connectivity_subscription_id" {
  type        = string
  nullable    = false
  description = "Connectivity subscription ID"
}

###############################################################
# POLICY - AMBA
###############################################################
variable "alert_severity" {
  type        = list(string)
  default     = ["Sev0", "Sev1", "Sev2", "Sev3", "Sev4"]
  nullable    = false
  description = "Severity levels for alert notifications"
}

variable "email_security_contact" {
  type        = string
  default     = ""
  nullable    = false
  description = "Email for Defender for Cloud security contact"
}

variable "defender_plans" {
  type = object({
    app_services                      = optional(string, "DeployIfNotExists")
    arm                               = optional(string, "DeployIfNotExists")
    containers                        = optional(string, "DeployIfNotExists")
    cosmos_dbs                        = optional(string, "DeployIfNotExists")
    cspm                              = optional(string, "DeployIfNotExists")
    key_vault                         = optional(string, "DeployIfNotExists")
    oss_db                            = optional(string, "DeployIfNotExists")
    servers                           = optional(string, "DeployIfNotExists")
    servers_vulnerability_assessments = optional(string, "DeployIfNotExists")
    sql                               = optional(string, "DeployIfNotExists")
    sql_on_vm                         = optional(string, "DeployIfNotExists")
    storage                           = optional(string, "DeployIfNotExists")
  })
  default     = {}
  description = <<-EOT
  Defender for Cloud plan activation, passed to Deploy-MDFC-Config-H224 via
  policy_assignments_to_modify. Each plan value must be either
  "DeployIfNotExists" (enables the plan at Standard pricing) or "Disabled"
  (skips the plan).

  Default: all plans enabled (pay-per-use with 0 resources ≈ 0 cost,
  auto-coverage when a workload is deployed). Override individual plans
  by setting them to "Disabled" if your org has a specific exclusion.

  Note: Defender for APIs is not exposed by the Deploy-MDFC-Config_20240319
  policySet and must be managed out-of-band (or via a future policy version).
  EOT
  nullable    = false

  validation {
    condition = alltrue([
      for k, v in var.defender_plans :
      contains(["DeployIfNotExists", "Disabled"], v)
    ])
    error_message = "Each defender_plans value must be 'DeployIfNotExists' or 'Disabled'."
  }
}

variable "amba_resource_group_name" {
  type        = string
  default     = "rg-amba-monitoring-001"
  nullable    = false
  description = "Resource group name for AMBA monitoring"
}

variable "mdfc_export_resource_group_name" {
  type        = string
  default     = "rg-alz-mdfc-export"
  nullable    = false
  description = "RG name for the MDFC continuous-export automation (created per subscription by the Deploy-MDFC-Config DINE policy)."
}

variable "service_health_resource_group_name" {
  type        = string
  default     = "rg-alz-service-health"
  nullable    = false
  description = "RG name for the Service Health alerts (created per subscription by the Deploy-SvcHealth-BuiltIn DINE policy)."
}

variable "amba_resource_group_tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags for the AMBA resource group"
}

variable "amba_disable_tag_name" {
  type        = string
  default     = "MonitorDisable"
  nullable    = false
  description = "Tag name to disable monitoring at resource level"
}

variable "amba_disable_tag_values" {
  type        = list(string)
  default     = ["true", "Test", "Dev", "Sandbox"]
  nullable    = false
  description = "Tag values to disable monitoring"
}

variable "action_group_email" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "Action group email addresses"
}

###############################################################
# DEPENDENCIES (outputs from other modules)
###############################################################
variable "ddos_protection_plan_id" {
  type        = string
  nullable    = false
  description = "DDoS Protection Plan resource ID"
}

variable "vmss_policy_not_scopes" {
  type        = list(string)
  default     = []
  nullable    = false
  description = <<-EOT
  Resource IDs to EXCLUDE (notScopes) from the VMSS monitoring / change-tracking
  DINE policy assignments at mg-lz (Deploy-VMSS-Monitoring, Deploy-VMSS-ChangeTrack).

  Typical use: AKS node resource groups (rg-...-aks-nodes) whose VMSS are managed by
  AKS and must not be governed by these policies — add one entry per AKS.

  Wired to `not_scopes` on both assignments via policy_assignments_to_modify
  (supported by avm-ptn-alz 0.21.0). Default [] leaves notScopes empty — the current
  state — so it is non-breaking. Previously this input was passed by the ALZ unit but
  NOT declared here, so Terraform silently discarded it (the exclusions never applied).
  EOT
}

variable "ama_identity_id" {
  type        = string
  nullable    = false
  description = "AMA User Assigned Identity ID"
}

variable "action_group_ids" {
  type        = list(string)
  nullable    = false
  description = "List of Action Group IDs"
}

variable "log_analytics_workspace_id" {
  type        = string
  nullable    = false
  description = "Full resource ID of the Log Analytics Workspace"
}

###############################################################
# POLICY - AMA DATA COLLECTION RULES
# Consumed by the ALZ AMA DINE policies to associate VMs / Arc machines
# with the right DCR. Wire these from the AlzManagement module outputs:
#   dcr_vm_insights_id / dcr_change_tracking_id / dcr_defender_sql_id
###############################################################
variable "dcr_vm_insights_id" {
  type        = string
  nullable    = false
  description = "Full resource ID of the VM Insights Data Collection Rule (AlzManagement output dcr_vm_insights_id)."
}

variable "dcr_change_tracking_id" {
  type        = string
  nullable    = false
  description = "Full resource ID of the Change Tracking & Inventory Data Collection Rule (AlzManagement output dcr_change_tracking_id)."
}

variable "dcr_defender_sql_id" {
  type        = string
  nullable    = false
  description = "Full resource ID of the Defender for SQL Data Collection Rule (AlzManagement output dcr_defender_sql_id)."
}

###############################################################
# POLICY - BACKUP
###############################################################
variable "backup_exclusion_tags" {
  type        = list(string)
  default     = ["NoBackup"]
  nullable    = false
  description = "Tags to exclude from VM Backup policy"
}

variable "aks_allowed_container_images_regex" {
  type        = string
  nullable    = false
  description = <<-EOT
  Regex of container-image references ALLOWED by the MCSB rule
  `ensureAllowedContainerImagesInKubernetesCluster` (Deploy-ASC-Monitoring @ mg-lzr).

  The ALZ default `^(.+){0}$` matches ONLY the empty string → no image can satisfy it →
  the rule is inert (produces phantom Gatekeeper violations that signal nothing). This
  overrides it with the real allowed registries.

  Default: MCR + any Azure Container Registry — `^(mcr\.microsoft\.com|[a-z0-9]+\.azurecr\.io)/.*$`.
  Deliberately NOT tied to a single ACR name: this is applied at mg-lzr (ALL landing zones),
  so each LZ's own ACR (cr…​.azurecr.io) must match without hardcoding. Public-internet
  registries (ghcr.io, docker.io, docker.n8n.io, quay.io, …) are intentionally excluded —
  mirror those images into an ACR rather than widening this pattern.

  AUDIT-phase value. When flipping the effect to `deny`, consider tightening `[a-z0-9]+` to
  the house naming pattern (e.g. `cr[a-z0-9]+`) to also exclude third-party ACRs. The effect
  itself (`allowedContainerImagesInKubernetesClusterEffect`) is NOT set by this module — it
  stays at the ALZ default (Audit); flip it only once violations are zero.

  Backslashes must be escaped for HCL: e.g. `\\.` for a literal dot.
  EOT
  default     = "^(mcr\\.microsoft\\.com|[a-z0-9]+\\.azurecr\\.io)/.*$"

  validation {
    # Reject a malformed regex at plan time (RE2). regexall throws on an invalid pattern.
    condition     = can(regexall(var.aks_allowed_container_images_regex, ""))
    error_message = "aks_allowed_container_images_regex must be a valid RE2 regular expression."
  }
}

variable "private_dns_zone_resource_group_name" {
  type        = string
  default     = null
  nullable    = true
  description = "Resource group for private DNS zones. Null means no specific RG is required by the DINE policy (distinct from empty string)."
}

###############################################################
# PROVIDER BEHAVIOUR / GOVERNANCE (avm-ptn-alz passthrough)
###############################################################
# These forward directly to Azure/avm-ptn-alz. Each defaults to the AVM's own
# default, so declaring them is a no-op until a caller overrides — but without
# them the input is silently dropped (undeclared TF_VAR).

variable "retries" {
  # Passthrough to avm-ptn-alz. Typed `any` because the upstream object is large
  # and nested (per-resource-type error_message_regex / interval / multiplier…);
  # the AVM module validates it. Default {} => the AVM applies its own defaults,
  # which already retry on eventual-consistency errors (e.g. AuthorizationFailed
  # on freshly created MGs). Override to add custom retry regexes.
  type        = any
  default     = {}
  nullable    = false
  description = "Retry settings forwarded to avm-ptn-alz (eventual consistency on fresh MG/policy/role deploys). Empty = AVM defaults."
}

variable "subscription_placement_destroy_behavior" {
  type        = string
  default     = "default"
  nullable    = false
  description = "Where subscriptions go when their placement is destroyed. One of: parent, intermediate_root, custom, default."
  validation {
    condition     = contains(["parent", "intermediate_root", "custom", "default"], var.subscription_placement_destroy_behavior)
    error_message = "Must be one of: parent, intermediate_root, custom, default."
  }
}

variable "subscription_placement_destroy_custom_target_management_group_id" {
  type        = string
  default     = null
  nullable    = true
  description = "Target management group id for subscriptions on destroy when subscription_placement_destroy_behavior = \"custom\"."
}

variable "policy_assignment_non_compliance_message_settings" {
  type = object({
    default_message = optional(string)            # null = pas de message par défaut (comportement AVM backwards-compat)
    merge_mode      = optional(string, "replace") # doit rester "replace" | "prefer_existing", jamais null (validation AVM)
  })
  default     = {}
  nullable    = false
  description = "Default non-compliance message settings applied to policy assignments by the alz provider. Empty = AVM defaults."
}
