###############################################################
# MODULE: AvdStack - Variables
#
# Composite that wires the AVD control plane (host pool + app
# groups + workspace, optional scaling plan) and, optionally, the
# session hosts — reusing the ../Avd* leaf submodules.
#
# Consumes EXISTING resource groups (repo convention): one for the
# control plane, one (override) for the session hosts. Everything
# else (KV, subnet, FSLogix share, gallery image) is referenced by
# ID and lives in its own RG.
###############################################################

###############################################################
# NAMING (shared) — each leaf module appends its own type prefix
# (vdpool-, vdws-, vdag-, vdscaling-, vm-).
###############################################################
variable "subscription_acronym" {
  type        = string
  description = "Subscription acronym (e.g. avd)."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  description = "Environment (e.g. nprd, prod)."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  description = "Region code of the AVD CONTROL PLANE (host pool/workspace/app groups/scaling plan), e.g. weu."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  description = "Workload suffix for the control-plane objects (host pool, workspace, scaling plan) unless overridden per component."
  default     = "avd"
  nullable    = false
}

###############################################################
# CONTROL-PLANE PLACEMENT (existing RG)
###############################################################
variable "location" {
  type        = string
  description = "Azure region of the AVD control plane. AVD metadata objects are region-bound; session hosts may live elsewhere."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Existing resource group for the AVD control-plane objects (host pool, app groups, workspace, scaling plan)."
  nullable    = false
}

###############################################################
# HOST POOL
###############################################################
variable "host_pool" {
  description = "Host pool configuration. A registration token is always created (create_registration_info = true) so the session hosts can join."
  type = object({
    workload                      = optional(string)
    type                          = optional(string, "Pooled")
    load_balancer_type            = optional(string, "BreadthFirst")
    maximum_sessions_allowed      = optional(number, 8)
    preferred_app_group_type      = optional(string, "Desktop")
    start_vm_on_connect           = optional(bool, true)
    public_network_access         = optional(string, "Disabled")
    custom_rdp_properties         = optional(string)
    friendly_name                 = optional(string)
    description                   = optional(string)
    registration_expiration_hours = optional(number, 48)
    scheduled_agent_updates = optional(object({
      enabled                   = optional(bool, false)
      timezone                  = optional(string)
      use_session_host_timezone = optional(bool, false)
      schedule = optional(list(object({
        day_of_week = string
        hour_of_day = number
      })), [])
    }))
    role_assignments = optional(map(object({
      role_definition_id_or_name       = string
      principal_id                     = string
      principal_type                   = optional(string, "Group")
      condition                        = optional(string)
      condition_version                = optional(string)
      description                      = optional(string)
      skip_service_principal_aad_check = optional(bool, false)
    })), {})
    lock = optional(object({
      kind = string
      name = optional(string)
    }))
  })
  default = {}
}

###############################################################
# APPLICATION GROUPS (map — bound to the host pool, associated to
# the workspace). Default: a single Desktop app group.
###############################################################
variable "application_groups" {
  description = "Map of application groups. Key = logical name (also the naming workload unless overridden, and the workspace association key). Desktop or RemoteApp. Assign 'Desktop Virtualization User' to end-user groups via role_assignments."
  type = map(object({
    type                         = optional(string, "Desktop")
    workload                     = optional(string)
    friendly_name                = optional(string)
    description                  = optional(string)
    default_desktop_display_name = optional(string)
    applications = optional(map(object({
      name                         = string
      path                         = string
      command_line_argument_policy = string
      friendly_name                = optional(string)
      description                  = optional(string)
      command_line_arguments       = optional(string)
      icon_path                    = optional(string)
      icon_index                   = optional(number, 0)
      show_in_portal               = optional(bool, true)
    })), {})
    role_assignments = optional(map(object({
      role_definition_id_or_name       = string
      principal_id                     = string
      principal_type                   = optional(string, "Group")
      condition                        = optional(string)
      condition_version                = optional(string)
      description                      = optional(string)
      skip_service_principal_aad_check = optional(bool, false)
    })), {})
    lock = optional(object({
      kind = string
      name = optional(string)
    }))
  }))
  default = {
    desktop = { type = "Desktop" }
  }
  nullable = false

  validation {
    condition     = length(var.application_groups) >= 1
    error_message = "At least one application group is required (the workspace needs something to expose)."
  }
}

###############################################################
# WORKSPACE
###############################################################
variable "workspace" {
  description = "Workspace configuration. All application_groups are associated to it automatically."
  type = object({
    workload                      = optional(string)
    friendly_name                 = optional(string)
    description                   = optional(string)
    public_network_access_enabled = optional(bool, false)
    role_assignments = optional(map(object({
      role_definition_id_or_name       = string
      principal_id                     = string
      principal_type                   = optional(string, "Group")
      condition                        = optional(string)
      condition_version                = optional(string)
      description                      = optional(string)
      skip_service_principal_aad_check = optional(bool, false)
    })), {})
    lock = optional(object({
      kind = string
      name = optional(string)
    }))
  })
  default = {}
}

###############################################################
# SCALING PLAN (optional — null = none)
###############################################################
variable "scaling_plan" {
  description = "Optional autoscale plan bound to the host pool. Null = no scaling plan. schedules is required when set."
  type = object({
    workload      = optional(string, "pooled")
    time_zone     = optional(string, "W. Europe Standard Time")
    friendly_name = optional(string)
    description   = optional(string)
    exclusion_tag = optional(string)
    enabled       = optional(bool, true) # scaling_plan_enabled on the host pool association
    schedules = map(object({
      days_of_week                         = set(string)
      ramp_up_start_time                   = string
      ramp_up_load_balancing_algorithm     = string
      ramp_up_minimum_hosts_percent        = optional(number)
      ramp_up_capacity_threshold_percent   = optional(number)
      peak_start_time                      = string
      peak_load_balancing_algorithm        = string
      ramp_down_start_time                 = string
      ramp_down_load_balancing_algorithm   = string
      ramp_down_minimum_hosts_percent      = number
      ramp_down_capacity_threshold_percent = number
      ramp_down_force_logoff_users         = bool
      ramp_down_wait_time_minutes          = number
      ramp_down_notification_message       = string
      ramp_down_stop_hosts_when            = string
      off_peak_start_time                  = string
      off_peak_load_balancing_algorithm    = string
    }))
    role_assignments = optional(map(object({
      role_definition_id_or_name       = string
      principal_id                     = string
      principal_type                   = optional(string, "Group")
      condition                        = optional(string)
      condition_version                = optional(string)
      description                      = optional(string)
      skip_service_principal_aad_check = optional(bool, false)
    })), {})
    lock = optional(object({
      kind = string
      name = optional(string)
    }))
  })
  default = null
}

###############################################################
# SESSION HOSTS (optional — null = control plane only)
# Defaults mirror ../AvdSessionHost so nothing is passed as null
# where the leaf module expects a real default.
###############################################################
variable "session_host" {
  description = "Session host configuration. Null = deploy the control plane only (add hosts later). When set, subnet_id, admin_password_kv_id and fslogix_vhd_location are required. Override resource_group_name/location/region_code to place hosts in a different (e.g. gwc) RG/region than the control plane."
  type = object({
    # Placement overrides (default to the control-plane RG/region).
    resource_group_name = optional(string)
    location            = optional(string)
    region_code         = optional(string)
    workload            = optional(string, "sh")

    # Required.
    subnet_id            = string
    admin_password_kv_id = string
    fslogix_vhd_location = string

    # VM sizing / image.
    vm_count                       = optional(number, 1)
    vm_size                        = optional(string, "Standard_D4s_v5")
    availability_zones             = optional(list(string), ["1", "2", "3"])
    accelerated_networking_enabled = optional(bool, true)
    image = optional(object({
      publisher = string
      offer     = string
      sku       = string
      version   = optional(string, "latest")
      }), {
      publisher = "microsoftwindowsdesktop"
      offer     = "windows-11"
      sku       = "win11-24h2-avd"
      version   = "latest"
    })
    image_plan = optional(object({
      name      = string
      publisher = string
      product   = string
    }))
    source_image_id = optional(string)
    os_disk = optional(object({
      storage_account_type = optional(string, "Premium_LRS")
      caching              = optional(string, "ReadWrite")
      disk_size_gb         = optional(number, 128)
      ephemeral            = optional(bool, true)
    }), {})

    # Identity / OS.
    admin_username             = optional(string, "azureadmin")
    admin_password_secret_name = optional(string, "sh-local-admin-password")
    computer_name_prefix       = optional(string)
    enable_trusted_launch      = optional(bool, true)
    encryption_at_host_enabled = optional(bool, true)
    license_type               = optional(string, "Windows_Client")
    patch_mode                 = optional(string, "AutomaticByPlatform")
    fslogix_profile_size_mb    = optional(number, 30000)

    role_assignments = optional(map(object({
      role_definition_id_or_name       = string
      principal_id                     = string
      principal_type                   = optional(string, "Group")
      condition                        = optional(string)
      condition_version                = optional(string)
      description                      = optional(string)
      skip_service_principal_aad_check = optional(bool, false)
    })), {})
    lock = optional(object({
      kind = string
      name = optional(string)
    }))
  })
  default = null
}

###############################################################
# TAGS
###############################################################
variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags applied to every resource in the stack."
}
