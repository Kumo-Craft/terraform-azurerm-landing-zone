###############################################################
# MODULE: AvdStack - Main
#
# Composition order / wiring:
#   host_pool (create_registration_info = true)
#     ├─ registration_token ─────────────► session_host
#     ├─ id ─────────────────────────────► application_group[*]
#     └─ id ─────────────────────────────► scaling_plan (optional)
#   application_group[*].id ── associations ─► workspace
###############################################################

###############################################################
# HOST POOL — token always created (session hosts need to join).
###############################################################
module "host_pool" {
  source = "../AvdHostPool"

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = coalesce(var.host_pool.workload, var.workload)

  location            = var.location
  resource_group_name = var.resource_group_name

  type                     = var.host_pool.type
  load_balancer_type       = var.host_pool.load_balancer_type
  maximum_sessions_allowed = var.host_pool.maximum_sessions_allowed
  preferred_app_group_type = var.host_pool.preferred_app_group_type
  start_vm_on_connect      = var.host_pool.start_vm_on_connect
  public_network_access    = var.host_pool.public_network_access
  custom_rdp_properties    = var.host_pool.custom_rdp_properties
  friendly_name            = var.host_pool.friendly_name
  description              = var.host_pool.description
  scheduled_agent_updates  = var.host_pool.scheduled_agent_updates

  create_registration_info      = true
  registration_expiration_hours = var.host_pool.registration_expiration_hours

  role_assignments = var.host_pool.role_assignments
  lock             = var.host_pool.lock
  tags             = var.tags
}

###############################################################
# APPLICATION GROUPS — one per map entry, bound to the host pool.
###############################################################
module "application_group" {
  source   = "../AvdApplicationGroup"
  for_each = var.application_groups

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = coalesce(each.value.workload, each.key)

  location            = var.location
  resource_group_name = var.resource_group_name
  host_pool_id        = module.host_pool.id

  type                         = each.value.type
  friendly_name                = each.value.friendly_name
  description                  = each.value.description
  default_desktop_display_name = each.value.default_desktop_display_name
  applications                 = each.value.applications

  role_assignments = each.value.role_assignments
  lock             = each.value.lock
  tags             = var.tags
}

###############################################################
# WORKSPACE — associates every application group above.
###############################################################
module "workspace" {
  source = "../AvdWorkspace"

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = coalesce(var.workspace.workload, var.workload)

  location            = var.location
  resource_group_name = var.resource_group_name

  friendly_name                 = var.workspace.friendly_name
  description                   = var.workspace.description
  public_network_access_enabled = var.workspace.public_network_access_enabled

  application_group_associations = { for k, m in module.application_group : k => m.id }

  role_assignments = var.workspace.role_assignments
  lock             = var.workspace.lock
  tags             = var.tags
}

###############################################################
# SCALING PLAN (optional) — bound to the host pool.
###############################################################
module "scaling_plan" {
  source = "../AvdScalingPlan"
  count  = var.scaling_plan == null ? 0 : 1

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.scaling_plan.workload

  location            = var.location
  resource_group_name = var.resource_group_name

  time_zone     = var.scaling_plan.time_zone
  friendly_name = var.scaling_plan.friendly_name
  description   = var.scaling_plan.description
  exclusion_tag = var.scaling_plan.exclusion_tag
  schedules     = var.scaling_plan.schedules

  host_pool_associations = {
    this = {
      hostpool_id          = module.host_pool.id
      scaling_plan_enabled = var.scaling_plan.enabled
    }
  }

  role_assignments = var.scaling_plan.role_assignments
  lock             = var.scaling_plan.lock
  tags             = var.tags
}

###############################################################
# SESSION HOSTS (optional) — join the host pool via its token.
# Placement can differ from the control plane (RG/region).
###############################################################
module "session_host" {
  source = "../AvdSessionHost"
  count  = var.session_host == null ? 0 : 1

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = coalesce(var.session_host.region_code, var.region_code)
  workload             = var.session_host.workload

  location            = coalesce(var.session_host.location, var.location)
  resource_group_name = coalesce(var.session_host.resource_group_name, var.resource_group_name)
  subnet_id           = var.session_host.subnet_id

  vm_count                       = var.session_host.vm_count
  vm_size                        = var.session_host.vm_size
  availability_zones             = var.session_host.availability_zones
  accelerated_networking_enabled = var.session_host.accelerated_networking_enabled
  image                          = var.session_host.image
  image_plan                     = var.session_host.image_plan
  source_image_id                = var.session_host.source_image_id
  os_disk                        = var.session_host.os_disk

  admin_username             = var.session_host.admin_username
  admin_password_kv_id       = var.session_host.admin_password_kv_id
  admin_password_secret_name = var.session_host.admin_password_secret_name
  computer_name_prefix       = var.session_host.computer_name_prefix
  enable_trusted_launch      = var.session_host.enable_trusted_launch
  encryption_at_host_enabled = var.session_host.encryption_at_host_enabled
  license_type               = var.session_host.license_type
  patch_mode                 = var.session_host.patch_mode

  hostpool_name               = module.host_pool.name
  hostpool_registration_token = module.host_pool.registration_token

  fslogix_vhd_location    = var.session_host.fslogix_vhd_location
  fslogix_profile_size_mb = var.session_host.fslogix_profile_size_mb

  role_assignments = var.session_host.role_assignments
  lock             = var.session_host.lock
  tags             = var.tags
}
