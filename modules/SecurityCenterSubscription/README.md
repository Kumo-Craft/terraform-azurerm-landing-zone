# SecurityCenterSubscription

Sets the **Microsoft Defender for Cloud security contact** at the **subscription** level, deployed via **azapi** against `Microsoft.Security/securityContacts@2023-12-01-preview`. Without a properly-shaped contact, high-severity Defender alerts notify nobody **and** the ALZ policy `Deploy-ASC-SecurityContacts` reports the subscription non-compliant.

## Why azapi (and not `azurerm_security_center_contact`)

The `azurerm_security_center_contact` resource only exposes the **legacy** schema — `email`, `phone`, `alert_notifications`, `alerts_to_admins` — and **cannot express `notificationsSources`** (verified against azurerm 4.81.0: there is no `notifications_sources` attribute). `Deploy-ASC-SecurityContacts` (the `securityEmailContact` component of the `Deploy-MDFC-Config` initiative) has a four-part existence condition:

1. `emails` contains the security email — ✅ (legacy could do this)
2. `isEnabled = true` — ✅
3. `notificationsSources[]` with `sourceType = "Alert"` and `Alert.minimalSeverity` — ✅
4. `notificationsSources[]` with `sourceType = "AttackPath"` and `AttackPath.minimalRiskLevel` — ❌ **impossible with the legacy resource**

So a subscription with a correctly-configured contact stayed **non-compliant** because part 4 could not be written. This module now owns the **full** `securityContacts/default` PUT via azapi, so the current schema (including `notificationsSources`) is expressed end-to-end.

> **The trap this avoids:** if the module wrote the legacy schema in a PUT, any `notificationsSources` set out-of-band would be **wiped on the next apply** (the same class of silent-reset that bit ContainerRegistry in PR #168). The rule here is: own `notificationsSources` end-to-end, or don't touch the field — never in-between.

## ⚠️ BREAKING CHANGE — resource migration (azurerm → azapi)

This release replaces `azurerm_security_center_contact.this` with `azapi_resource.this`. That is a resource-**address** change, and the input interface changed too. No per-module CHANGELOG exists in this repo (single global SemVer), so the migration is documented here.

**State migration — `moved` block (azapi's official azurerm→azapi path).** The module carries
`moved { from = azurerm_security_center_contact.this  to = azapi_resource.this }`. On upgrade
this is a pure **state relabel** (`0 to add, 0 to change, 0 to destroy`); the next plan is an
in-place **update** that adds `notificationsSources`. The real `securityContacts/default` is
never destroyed or recreated. Requires Terraform ≥ 1.8 + azapi ≥ 2.1 (both satisfied here);
`azurerm` stays in `required_providers` only so the `from` type resolves.

> **⚠️ Validate the first upgrade on ONE non-prod subscription** — the plan must show
> `0 to destroy`. azapi documents the move for root-module resources; if the cross-type
> state-move does not apply cleanly for a resource nested in this child module, the plan will
> reveal it (a destroy/create instead of a move). Fallback in that case:
> ```bash
> terraform state rm  'module.<x>.azurerm_security_center_contact.this'
> terraform import    'module.<x>.azapi_resource.this' \
>   '/subscriptions/<SUB_ID>/providers/Microsoft.Security/securityContacts/default'
> ```

**Interface changes:**
- **Removed** `alert_notifications` and `alerts_to_admins` — these fields do not exist in the 2023-12-01-preview schema. Map them as: `alert_notifications` → `enabled` (`isEnabled`); `alerts_to_admins` → `notifications_by_role` (`notificationsByRole`, defaulting to `{ state = "On", roles = ["Owner"] }`, which preserves the old `alerts_to_admins = true` behaviour).
- **Added** `enabled`, `notifications_by_role`, `notifications_sources`.
- `subscription_id` is now **functional** (the azapi `parent_id`), not a decorative assertion — this supersedes the client_config precondition guardrail from PR #148, which is removed.

## Usage

```hcl
module "security_center_subscription" {
  source = "git::https://dev.azure.com/azure-forge/Modules/_git/Modules//modules/SecurityCenterSubscription?ref=v0.3.0"

  # Functional: this is the parent_id — the contact is created on THIS subscription.
  subscription_id = "00000000-0000-0000-0000-000000000000"

  email = "soc@example.com"
  phone = "+352 123 456" # optional

  # ALZ-compliant posture — satisfies Deploy-ASC-SecurityContacts:
  notifications_sources = {
    alert       = { minimal_severity   = "High" }     # High | Medium | Low
    attack_path = { minimal_risk_level = "Critical" } # Critical | High | Medium | Low
  }

  # Defaults shown (preserve prior behaviour); override or set null to omit:
  # enabled               = true
  # notifications_by_role = { state = "On", roles = ["Owner"] }
}
```

## Gotchas (by design)

1. **`name` is hardcoded to `"default"`** — Azure allows exactly one security contact per subscription, only under that name. Not exposed.
2. **`notifications_sources` defaults to `null` → omitted.** Nothing is imposed: the contact is created without a `notificationsSources` block, preserving current behaviour. Declare it to make `Deploy-ASC-SecurityContacts` compliant. (Note: leaving it null keeps the subscription non-compliant on that policy — that is a deliberate opt-in, since forcing Critical/High on every consumer would be a posture decision.)
3. **No `lock`** — the contact is a subscription-scoped setting, not an RG resource.

## SecurityCenter* family & remaining gap

- **Defender plans / pricing** → [`SecurityCenterPricing`](../SecurityCenterPricing).
- **Security contact** → this module.
- **Settings (MCAS / WDATP data exports)** via `azurerm_security_center_setting` → still open, out of scope here.

See also [`SecurityCenterWorkspace`](../SecurityCenterWorkspace).

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azapi | ~> 2.4 |
| azurerm | ~> 4.0 (only for the `removed` block's type resolution) |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| subscription_id | Target subscription (bare GUID or `/subscriptions/<guid>` path). Used as the azapi `parent_id`. | `string` | -- | Yes |
| email | Security contact email(s); `;`/`,`-separated for multiple (→ `properties.emails`). | `string` | -- | Yes |
| phone | Optional contact phone (`properties.phone`; omitted when null). | `string` | `null` | No |
| enabled | `properties.isEnabled`. | `bool` | `true` | No |
| notifications_by_role | `properties.notificationsByRole` — `{ state = "On"\|"Off", roles = [AccountAdmin\|Contributor\|Owner\|ServiceAdmin] }`. `null` omits it. | `object` | `{ state = "On", roles = ["Owner"] }` | No |
| notifications_sources | `properties.notificationsSources` — `{ alert = { minimal_severity }, attack_path = { minimal_risk_level } }`. `null` omits it (nothing imposed). | `object` | `null` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | Security contact ID (`.../securityContacts/default`) |
| name | Always `"default"` |
| email | Configured contact email(s) |
| notifications_sources | The effective `notificationsSources[]` written (empty list when none declared) |

## Testing

`tests/basic.tftest.hcl` — plan-time, `mock_provider "azapi"` (+ mocked `azurerm` for the `removed` block): parent_id normalization (bare/path), Alert+AttackPath emission, Alert-only default severity, multi-email, and validators (empty sources object, bad severity/risk-level, bad subscription_id, bad role state/roles, malformed email). Run: `terraform init -backend=false && terraform test`.

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azapi | ~> 2.4 |
| azurerm | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| azapi | ~> 2.4 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azapi_resource.this](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| email | Security contact email(s) that receive Microsoft Defender for Cloud notifications. Azure supports multiple recipients separated by ';' or ',' (maps to properties.emails). | `string` | n/a | yes |
| subscription\_id | Subscription the Microsoft Defender for Cloud security contact applies to. Accepts a<br>bare GUID or a full /subscriptions/<guid> path (normalized in main.tf).<br><br>With the azapi rewrite this is now FUNCTIONAL, not just an assertion: it is the<br>`parent_id` of the securityContacts resource, so the contact is created on exactly this<br>subscription (the azapi provider's credentials must have access to it). This supersedes<br>the previous client\_config precondition guardrail (PR #148), which existed only because<br>the old azurerm\_security\_center\_contact had no subscription argument. | `string` | n/a | yes |
| enabled | Whether the security contact is enabled (maps to properties.isEnabled). Default true — the whole point of the module. Replaces the legacy alert\_notifications flag. | `bool` | `true` | no |
| notifications\_by\_role | Email notifications to holders of specific RBAC roles on the subscription (maps to<br>properties.notificationsByRole). Replaces the legacy alerts\_to\_admins flag.<br><br>- state : "On" or "Off". Default "On".<br>- roles : subset of AccountAdmin / Contributor / Owner / ServiceAdmin. Default ["Owner"].<br><br>Default `{ state = "On", roles = ["Owner"] }` preserves the previous alerts\_to\_admins=true<br>behaviour and matches the live state on sub-pgroup-shared-corp-prod. Set to `null` to omit<br>the block entirely (Defender then sends role notifications to no one). | <pre>object({<br>    state = optional(string, "On")<br>    roles = optional(list(string), ["Owner"])<br>  })</pre> | `{}` | no |
| notifications\_sources | Notification sources evaluated for email delivery (maps to properties.notificationsSources,<br>API 2023-12-01-preview). This is the field the legacy azurerm\_security\_center\_contact could<br>not express, which kept Deploy-ASC-SecurityContacts non-compliant despite a configured contact.<br><br>- alert.minimal\_severity      : "High" / "Medium" / "Low"  (sourceType "Alert")<br>- attack\_path.minimal\_risk\_level : "Critical" / "High" / "Medium" / "Low" (sourceType "AttackPath")<br><br>Default `null` → the block is OMITTED (preserves current behaviour; nothing imposed). Declare<br>it to satisfy the policy's existence condition — the ALZ-compliant posture is<br>`{ alert = { minimal_severity = "High" }, attack_path = { minimal_risk_level = "Critical" } }`.<br>Provide at least one of alert / attack\_path when the object is set. | <pre>object({<br>    alert = optional(object({<br>      minimal_severity = optional(string, "High")<br>    }))<br>    attack_path = optional(object({<br>      minimal_risk_level = optional(string, "Critical")<br>    }))<br>  })</pre> | `null` | no |
| phone | Optional security contact phone number (maps to properties.phone; omitted when null). | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| email | The configured security contact email(s) (properties.emails). |
| id | The ID of the security contact (.../providers/Microsoft.Security/securityContacts/default). |
| name | The security contact name — always "default" (Azure allows only one, under this name). |
| notifications\_sources | The effective notificationsSources[] written to the contact (empty list when none declared). |
<!-- END_TF_DOCS -->
