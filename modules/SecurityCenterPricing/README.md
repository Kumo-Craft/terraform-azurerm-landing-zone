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
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/SecurityCenterPricing?ref=v0.3.0"

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
