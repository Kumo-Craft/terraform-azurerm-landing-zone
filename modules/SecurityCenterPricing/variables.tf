###############################################################
# MODULE: SecurityCenterPricing - Variables
###############################################################

variable "plans" {
  type = map(object({
    # Secure-by-default (CKV_AZURE_19): tier defaults to
    # "Standard" (Defender ON) when omitted for a given resource_type.
    # ⚠️ COST: "Standard" facture TOUTES les ressources de ce type dans la
    #    sub. Passer explicitement tier = "Free" pour désactiver un plan.
    tier    = optional(string, "Standard")
    subplan = optional(string)
    extension = optional(list(object({
      name                            = string
      additional_extension_properties = optional(map(string))
    })), [])
  }))
  nullable    = false
  description = <<-EOT
    Plans Defender for Cloud à activer, clés par resource_type (la clé de
    map EST le resource_type — ex. "VirtualMachines", "StorageAccounts",
    "KeyVaults", "Containers", "CloudPosture", "Arm", "Dns", "Api", ...).
    La liste des resource_type valides évolue côté Azure — le provider la
    valide au plan, donc le module ne la fige pas ici.

      - tier      : "Free" ou "Standard". Défaut = "Standard" (secure-by-default,
                    Defender ON) — ⚠️ impact coût, mettre "Free" pour désactiver.
      - subplan   : variante optionnelle (ex. "P1"/"P2" pour VirtualMachines,
                    "DefenderForStorageV2" pour StorageAccounts). Omettre sinon.
                    Immutable (ForceNew).
      - extension : sous-fonctionnalités Defender (surtout pour CloudPosture /
                    VirtualMachines) — ex. AgentlessVmScanning,
                    SensitiveDataDiscovery, ContainerRegistriesVulnerabilityAssessments,
                    AgentlessDiscoveryForKubernetes. Une extension non déclarée
                    n'est PAS activée. `additional_extension_properties` = paires
                    clé/valeur requises par certaines extensions (ex. ExclusionTags).
  EOT

  validation {
    condition     = alltrue([for p in values(var.plans) : contains(["Free", "Standard"], p.tier)])
    error_message = "Chaque tier doit valoir \"Free\" ou \"Standard\"."
  }

  validation {
    condition = alltrue([
      for p in values(var.plans) : alltrue([for e in p.extension : length(trimspace(e.name)) > 0])
    ])
    error_message = "Chaque extension.name doit être non vide."
  }
}
