# SecurityCenterPricing

Active des plans **Microsoft Defender for Cloud** (pricing tiers) sur une souscription, via `azurerm_security_center_subscription_pricing` (`Microsoft.Security`). Un plan par `resource_type`, avec support des **extensions** Defender CSPM / Servers.

## ⚠️ Points cruciaux

- **Scope = le provider, pas un argument.** `azurerm_security_center_subscription_pricing` n'a **aucun** argument de scope/subscription — il s'applique **toujours** à la souscription du provider `azurerm`. Assure-toi que le provider (via son `subscription_id` / la service connection) cible la bonne sub.
- **IAM.** Le principal déployeur a besoin d'**Owner** ou **Security Admin** sur la sub. `Contributor` → **403** sur `Microsoft.Security/pricings`.
- **Suppression = reset à `Free`.** Retirer une entrée de `plans` (ou détruire le module) **remet le plan à `Free`** pour ce `resource_type`.
- **Coût.** Passer un type en `Standard` facture **toutes** les ressources de ce type dans la sub.

## Pas de naming / RG / tags / lock

La ressource est un **singleton par `resource_type` au niveau souscription** : pas de nom, pas de resource group, pas de tags, pas de management lock. Le module n'expose donc aucune de ces conventions maison (à dessein).

## Usage

```hcl
module "defender_plans" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/SecurityCenterPricing?ref=v0.3.0"

  plans = {
    VirtualMachines = { tier = "Standard", subplan = "P2" }
    StorageAccounts = { tier = "Standard", subplan = "DefenderForStorageV2" }
    KeyVaults       = { tier = "Standard" }
    Arm             = { tier = "Standard" }
    Containers      = { tier = "Standard" }

    # Defender CSPM + ses sous-fonctionnalités
    CloudPosture = {
      tier = "Standard"
      extension = [
        { name = "AgentlessVmScanning", additional_extension_properties = { ExclusionTags = "[]" } },
        { name = "SensitiveDataDiscovery" },
        { name = "ContainerRegistriesVulnerabilityAssessments" },
        { name = "AgentlessDiscoveryForKubernetes" },
      ]
    }
  }
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `plans` | `map(object)` | — (required) | Plans à activer, **clés par `resource_type`** (voir ci-dessous). |

### `plans[<resource_type>]`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `tier` | `string` | `Standard` | `Free` ou `Standard`. **Défaut `Standard`** (secure-by-default, Defender ON) — ⚠️ impact coût : facture toutes les ressources du type. Mettre `Free` pour désactiver. |
| `subplan` | `string` | `null` | Variante (ex. `P1`/`P2`, `DefenderForStorageV2`). ForceNew. |
| `extension` | `list(object({ name, additional_extension_properties }))` | `[]` | Sous-fonctionnalités Defender. Une extension non déclarée n'est pas activée. |

**`resource_type`** (clé de map) — valeurs valides (au 2026-07, provider azurerm 4.81) : `AI`, `Api`, `AppServices`, `ContainerRegistry`, `KeyVaults`, `KubernetesService`, `SqlServers`, `SqlServerVirtualMachines`, `StorageAccounts`, `VirtualMachines`, `Arm`, `Dns`, `OpenSourceRelationalDatabases`, `Containers`, `CosmosDbs`, `CloudPosture`. La liste **évolue côté Azure** — le module ne la fige pas (le provider la valide au plan), il valide seulement `tier`.

## Outputs

| Name | Description |
|------|-------------|
| `enabled_plans` | Map `resource_type` => `"tier"` ou `"tier/subplan"`. |
| `plan_ids` | Map `resource_type` => resource ID du plan. |

Pas d'output `resource` brut — exposer l'objet complet ferait remonter d'éventuels attributs dépréciés du provider en warnings de `plan` (convention maison depuis les curations FlowLogs / KeyVault / StorageAccount).

## Testing

`tests/basic.tftest.hcl` — plan-time, `mock_provider "azurerm"` : mapping tier/subplan, format `enabled_plans`, bloc `extension`, et validators (tier hors enum, nom d'extension vide). Run : `terraform init -backend=false && terraform test`.

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

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_security_center_subscription_pricing.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/security_center_subscription_pricing) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| plans | Plans Defender for Cloud à activer, clés par resource\_type (la clé de<br>map EST le resource\_type — ex. "VirtualMachines", "StorageAccounts",<br>"KeyVaults", "Containers", "CloudPosture", "Arm", "Dns", "Api", ...).<br>La liste des resource\_type valides évolue côté Azure — le provider la<br>valide au plan, donc le module ne la fige pas ici.<br><br>  - tier      : "Free" ou "Standard". Défaut = "Standard" (secure-by-default,<br>                Defender ON) — ⚠️ impact coût, mettre "Free" pour désactiver.<br>  - subplan   : variante optionnelle (ex. "P1"/"P2" pour VirtualMachines,<br>                "DefenderForStorageV2" pour StorageAccounts). Omettre sinon.<br>                Immutable (ForceNew).<br>  - extension : sous-fonctionnalités Defender (surtout pour CloudPosture /<br>                VirtualMachines) — ex. AgentlessVmScanning,<br>                SensitiveDataDiscovery, ContainerRegistriesVulnerabilityAssessments,<br>                AgentlessDiscoveryForKubernetes. Une extension non déclarée<br>                n'est PAS activée. `additional_extension_properties` = paires<br>                clé/valeur requises par certaines extensions (ex. ExclusionTags). | <pre>map(object({<br>    # Secure-by-default (CKV_AZURE_19): tier defaults to<br>    # "Standard" (Defender ON) when omitted for a given resource_type.<br>    # ⚠️ COST: "Standard" facture TOUTES les ressources de ce type dans la<br>    #    sub. Passer explicitement tier = "Free" pour désactiver un plan.<br>    tier    = optional(string, "Standard")<br>    subplan = optional(string)<br>    extension = optional(list(object({<br>      name                            = string<br>      additional_extension_properties = optional(map(string))<br>    })), [])<br>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| enabled\_plans | Map resource\_type => "tier" ou "tier/subplan" des plans configurés. |
| plan\_ids | Map resource\_type => resource ID du plan (/subscriptions/../providers/Microsoft.Security/pricings/<type>). |
<!-- END_TF_DOCS -->
