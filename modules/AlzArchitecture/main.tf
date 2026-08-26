###############################################################
# Module AlzArchitecture - ALZ Management Groups + Policies
###############################################################
# Wraps Azure/avm-ptn-alz/azurerm
# Creates: Management Group hierarchy, subscription placement,
#          policy assignments (AMBA, DDoS, Defender, Backup)
###############################################################

module "alz_architecture" {
  source             = "Azure/avm-ptn-alz/azurerm"
  version            = "0.21.0"
  architecture_name  = var.architecture_name
  parent_resource_id = var.management_root_id
  location           = var.location

  # ── Subscription Placement ──────────────────────────────────
  subscription_placement                                           = var.subscription_placement
  subscription_placement_destroy_behavior                          = var.subscription_placement_destroy_behavior
  subscription_placement_destroy_custom_target_management_group_id = var.subscription_placement_destroy_custom_target_management_group_id

  # ── Hierarchy Settings ─────────────────────────────────────
  management_group_hierarchy_settings = var.management_group_hierarchy_settings

  # ── Provider behaviour (eventual consistency + non-compliance msgs) ──
  retries                                           = var.retries
  policy_assignment_non_compliance_message_settings = var.policy_assignment_non_compliance_message_settings

  # ── Policy Assignments Modifications ────────────────────────
  policy_assignments_to_modify = {
    # NOTE: MG names are environment-agnostic (single platform, CAF-aligned) — clean ids
    # without env suffix. The key must match the management group id created by the
    # architecture definition. If the ALZ library renames the LZ MG (e.g. between major AVM
    # releases), this modification silently no-ops (key not found = no change). Re-verify
    # after AVM bumps.
    "mg-lzr" = {
      policy_assignments = {
        # Deploy-AMBA-Notification retiré : AMBA n'est plus déployé (archétypes
        # amba_* retirés de core.json). À remettre quand AMBA sera rebranché.
        Deploy-MDFC-Config-H224 = {
          parameters = {
            emailSecurityContact = jsonencode({ value = var.email_security_contact })
            # ${default_location} n'est PAS résolu par le provider alz dans les VALEURS de
            # params (seulement pour la location de la ressource assignation). Sans override,
            # la remédiation DINE crée le RG d'export MDFC en "${default_location}" littéral →
            # InvalidLocation → deploymentId = null. On force la région explicitement.
            ascExportResourceGroupLocation = jsonencode({ value = var.location })
            # Defender plans — activated everywhere under mg-lzr. Most plans
            # are pay-per-use on actual resources: zero resources ≈ zero
            # cost, but coverage is automatic as soon as a workload of that
            # type arrives. Cleaner than maintaining exemptions + missing
            # coverage on first deployment.
            #
            # Note: Deploy-MDFC-Config_20240319 policySet does NOT expose
            # an enableAscForApis parameter — Defender for APIs must be
            # managed separately (out-of-band or via another assignment).
            enableAscForAppServices                     = jsonencode({ value = var.defender_plans.app_services })
            enableAscForArm                             = jsonencode({ value = var.defender_plans.arm })
            enableAscForContainers                      = jsonencode({ value = var.defender_plans.containers })
            enableAscForCosmosDbs                       = jsonencode({ value = var.defender_plans.cosmos_dbs })
            enableAscForCspm                            = jsonencode({ value = var.defender_plans.cspm })
            enableAscForKeyVault                        = jsonencode({ value = var.defender_plans.key_vault })
            enableAscForOssDb                           = jsonencode({ value = var.defender_plans.oss_db })
            enableAscForServers                         = jsonencode({ value = var.defender_plans.servers })
            enableAscForServersVulnerabilityAssessments = jsonencode({ value = var.defender_plans.servers_vulnerability_assessments })
            enableAscForSql                             = jsonencode({ value = var.defender_plans.sql })
            enableAscForSqlOnVm                         = jsonencode({ value = var.defender_plans.sql_on_vm })
            enableAscForStorage                         = jsonencode({ value = var.defender_plans.storage })
          }
        }
        # Même souci de placeholder : Deploy-SvcHealth-BuiltIn crée son RG d'alertes
        # en "${default_location}" littéral → InvalidLocation. On force la région.
        # Hérité de mg-lzr → couvre security-prod et toute la landing zone (un seul override).
        Deploy-SvcHealth-BuiltIn = {
          parameters = {
            resourceGroupLocation = jsonencode({ value = var.location })
          }
        }
      }
    }
    # DDoS (défaut ALZ) : la lib pose Enable-DDoS-VNET — avec un ddosPlan
    # placeholder — sur connectivity ET landing_zones, donc le hub ET toute la
    # landing zone sont protégés. On y injecte le vrai plan aux deux scopes.
    "mg-con" = {
      policy_assignments = {
        Enable-DDoS-VNET = {
          parameters = {
            ddosPlan = jsonencode({ value = var.ddos_protection_plan_id })
          }
        }
      }
    }
    "mg-lz" = {
      policy_assignments = {
        Enable-DDoS-VNET = {
          parameters = {
            ddosPlan = jsonencode({ value = var.ddos_protection_plan_id })
          }
        }
        # Workaround bug lib AMBA 2026.06.1 : Deploy-AMBA-VMSS a perdu son mapping
        # default-value amba_alz_management_subscription_id → ALZManagementSubscriptionId
        # reste vide → role assignment arg-reader en /subscriptions// → InvalidSubscriptionId.
        # On set la sub explicitement. À retirer quand la lib AMBA re-mappe VMSS.
        Deploy-AMBA-VMSS = {
          parameters = {
            ALZManagementSubscriptionId              = jsonencode({ value = var.management_subscription_id })
            BYOUserAssignedManagedIdentityResourceId = jsonencode({ value = var.ama_identity_id })
            # + même bug lib 2026.06.1 : VMSS aussi absent du mapping
            #   amba_alz_resource_group_* → reste sur rg-amba-alz-prod-001/eastus en
            #   dur. On aligne explicitement sur ses frères (rg-amba-monitoring-001/gwc).
            #   À retirer quand la lib AMBA re-mappe VMSS.
            ALZMonitorResourceGroupName     = jsonencode({ value = var.amba_resource_group_name })
            ALZMonitorResourceGroupLocation = jsonencode({ value = var.location })
            ALZMonitorResourceGroupTags     = jsonencode({ value = var.amba_resource_group_tags })
          }
        }
      }
    }
    # Même correctif VMSS sur le MG platform (amba_platform y assigne aussi Deploy-AMBA-VMSS).
    "mg-plat" = {
      policy_assignments = {
        Deploy-AMBA-VMSS = {
          parameters = {
            ALZManagementSubscriptionId              = jsonencode({ value = var.management_subscription_id })
            BYOUserAssignedManagedIdentityResourceId = jsonencode({ value = var.ama_identity_id })
            # + même bug lib 2026.06.1 : VMSS aussi absent du mapping
            #   amba_alz_resource_group_* → reste sur rg-amba-alz-prod-001/eastus en
            #   dur. On aligne explicitement sur ses frères (rg-amba-monitoring-001/gwc).
            #   À retirer quand la lib AMBA re-mappe VMSS.
            ALZMonitorResourceGroupName     = jsonencode({ value = var.amba_resource_group_name })
            ALZMonitorResourceGroupLocation = jsonencode({ value = var.location })
            ALZMonitorResourceGroupTags     = jsonencode({ value = var.amba_resource_group_tags })
          }
        }
      }
    }
    "mg-idt" = {
      policy_assignments = {
        Deploy-VM-Backup = {
          parameters = {
            exclusionTagValue = jsonencode({ value = var.backup_exclusion_tags })
          }
        }
      }
    }
  }

  # ── Policy Default Values ───────────────────────────────────
  policy_default_values = {
    amba_alz_management_subscription_id            = jsonencode({ value = var.management_subscription_id })
    amba_alz_resource_group_location               = jsonencode({ value = var.location })
    amba_alz_resource_group_name                   = jsonencode({ value = var.amba_resource_group_name })
    amba_alz_resource_group_tags                   = jsonencode({ value = var.amba_resource_group_tags })
    amba_alz_byo_user_assigned_managed_identity_id = jsonencode({ value = var.ama_identity_id })
    amba_alz_disable_tag_name                      = jsonencode({ value = var.amba_disable_tag_name })
    amba_alz_disable_tag_values                    = jsonencode({ value = var.amba_disable_tag_values })
    amba_alz_action_group_email                    = jsonencode({ value = var.action_group_email })
    amba_alz_byo_action_group                      = jsonencode({ value = var.action_group_ids })
    log_analytics_workspace_id                     = jsonencode({ value = var.log_analytics_workspace_id })
    # AMA Data Collection Rules — the DINE policies associate VMs/Arc machines
    # with these DCRs. Wire them from the AlzManagement module's outputs
    # (dcr_vm_insights_id / dcr_change_tracking_id / dcr_defender_sql_id).
    ama_vm_insights_data_collection_rule_id     = jsonencode({ value = var.dcr_vm_insights_id })
    ama_change_tracking_data_collection_rule_id = jsonencode({ value = var.dcr_change_tracking_id })
    ama_mdfc_sql_data_collection_rule_id        = jsonencode({ value = var.dcr_defender_sql_id })
    # Friendly RG names for the DINE-created RGs (MDFC export + Service Health).
    # These keys MUST be declared in the lib's alz_policy_default_values.json —
    # unlike default_location (undeclared → provider hard-fails, see #10884).
    resource_group_name_mdfc                  = jsonencode({ value = var.mdfc_export_resource_group_name })
    resource_group_name_service_health_alerts = jsonencode({ value = var.service_health_resource_group_name })
    private_dns_zone_subscription_id          = jsonencode({ value = var.connectivity_subscription_id })
    private_dns_zone_region                   = jsonencode({ value = var.location })
    private_dns_zone_resource_group_name      = jsonencode({ value = coalesce(var.private_dns_zone_resource_group_name, "") })
  }
}
