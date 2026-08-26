# TlsSelfSignedCert

Generates a self-signed TLS certificate (RSA private key + X.509 cert via the `tls` provider) and imports it into an existing Azure Key Vault as a Certificate object. Suitable for internal/non-prod use cases where browser trust is not required: the cert chain is rejected by browsers, but TLS handshakes succeed and all origin/redirect checks pass on VPN-only or cluster-internal traffic.

**Typical use cases:**
- Argo CD / Grafana / Prometheus UI on a VPN-only AKS cluster
- Internal-only nginx Ingress fronted by AKS Application Routing add-on
- Kafka broker mTLS (client + server certs, non-public)

## Security warnings

> **State security warning**: The RSA private key is stored in Terraform state as part of `tls_private_key.this.private_key_pem`. Ensure your Terraform backend uses encryption at rest and RBAC-protected access — Azure Storage Account with encryption and state locking via Cosmos DB, or Terraform Cloud with Sentinel policies.

> **No `private_key_pem` output by design**: This module is KV-only — the private key PEM is NOT exposed as an output. The private key material is imported into Key Vault and accessed at runtime via the KV secret URI; exposing it as a Terraform output would expand the blast radius of a state file compromise. If a non-KV use case is required (e.g. a Kubernetes Secret populated via Helm, a separate PKI store), fork this module and add `output "private_key_pem" { value = tls_private_key.this.private_key_pem ; sensitive = true }` as an explicit opt-in — the `sensitive = true` marker is mandatory because `tls_private_key.this` propagates sensitivity to all derived outputs.

> **PKCS#8 note**: The module uses `private_key_pem_pkcs8` (PKCS#8, `-----BEGIN PRIVATE KEY-----`) when concatenating the PEM bundle for Azure Key Vault import. Passing PKCS#1 (`-----BEGIN RSA PRIVATE KEY-----`, attribute `private_key_pem`) causes a `400 "PEM X.509 certificate content is in an unexpected format"` error from the KV import API with no useful diagnostic. This is non-obvious and documented inline in main.tf.

> **RBAC prerequisite**: The identity running `terraform apply` (service principal, managed identity, or user) must hold the **Key Vault Certificates Officer** role (to import certificates) and **Key Vault Secrets Officer** role (KV also stores the cert as a secret) on the target Key Vault **before** applying. Any downstream reader (e.g. AKS App Routing UAMI, CSI driver) must hold **Key Vault Secrets User** to pull the cert at runtime.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| tls | ~> 4.0 |

## Breaking changes

### v0.2.70 — `validity_days` default changed 1825 → 365

The default certificate validity period has been reduced from 1825 days (5 years) to 365 days (1 year). This aligns with modern CA/Browser Forum guidance for short-lived certificates.

**Migration**: Callers that relied on the implicit 5-year default MUST explicitly set `validity_days = 1825` before upgrading, otherwise Terraform will plan a certificate replacement:

```hcl
# Add this to preserve existing 5-year behaviour
validity_days = 1825
```

Note: Certificates already issued will remain valid until their original expiry date. Only new certificates (or the next rotation cycle) are affected.

## Usage

### Standalone — semantic cert name (recommended for most use cases)

```hcl
module "tls_cert" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/TlsSelfSignedCert?ref=v0.2.70"

  cert_name    = "lb-internal-mtls"
  key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-prod-gwc-security/providers/Microsoft.KeyVault/vaults/kv-mgm-prod-gwc-sec"

  common_name  = "*.shc.az.epttst.lu"
  dns_names    = ["*.shc.az.epttst.lu", "shc.az.epttst.lu"]
  organization = "Post Luxembourg"

  validity_days = 365
  key_size      = 2048

  tags = { Environment = "nonprod" }
}
```

### Standalone — computed naming (standard naming vars)

```hcl
module "tls_cert" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/TlsSelfSignedCert?ref=v0.2.70"

  # cert_name is null → name computed as cert-{acr}-{env}-{region}-{workload}
  subscription_acronym = "aks"
  environment          = "nprd"
  region_code          = "gwc"
  workload             = "ingress"
  location             = "germanywestcentral"

  key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-aks-nprd-gwc-security/providers/Microsoft.KeyVault/vaults/kv-aks-nprd-gwc-sec"

  common_name = "*.aks.az.epttst.lu"
  dns_names   = ["*.aks.az.epttst.lu"]

  tags = { Environment = "nonprod" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/TlsSelfSignedCert"
}

inputs = {
  cert_name    = "lb-internal-mtls"
  key_vault_id = dependency.keyvault.outputs.id

  common_name  = "*.${local.domain}"
  dns_names    = ["*.${local.domain}", local.domain]
  organization = "Post Luxembourg"

  validity_days = 1825
  key_size      = 2048

  tags = include.root.inputs.common_tags
}
```

### AKS App Routing CSI annotation

The `secret_versionless_id` output is the value for the `kubernetes.azure.com/tls-cert-keyvault-uri` annotation on the Ingress. Using the versionless URI ensures the CSI driver always pulls the latest rotated version.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: my-namespace
  annotations:
    kubernetes.azure.com/tls-cert-keyvault-uri: "<secret_versionless_id output value>"
    # e.g. https://kv-aks-nprd-gwc-sec.vault.azure.net/secrets/lb-internal-mtls
spec:
  ingressClassName: webapprouting.kubernetes.azure.com
  tls:
    - hosts:
        - "*.shc.az.epttst.lu"
      secretName: tls-lb-internal-mtls   # CSI driver materializes the KV secret here
  rules:
    - host: "my-app.shc.az.epttst.lu"
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app
                port:
                  number: 80
```

To grant the App Routing UAMI access (run once per cluster/KV pair):

```hcl
resource "azurerm_role_assignment" "app_routing_kv_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_kubernetes_cluster.this.web_app_routing[0].web_app_routing_identity[0].object_id
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cert_name | Certificate name in Key Vault (1-127 chars, `[a-zA-Z0-9-]`). If null, computed from naming vars. | `string` | `null` | One of `cert_name` or all naming vars |
| subscription_acronym | Subscription acronym (e.g. mgm). Used when `cert_name` is null. | `string` | `null` | No |
| environment | Environment (e.g. prod, nprd). Used when `cert_name` is null. | `string` | `null` | No |
| region_code | Region code (e.g. gwc, weu). Used when `cert_name` is null. | `string` | `null` | No |
| location | Azure region (e.g. germanywestcentral). | `string` | `null` | No |
| workload | Workload component (e.g. ingress). Used when `cert_name` is null. | `string` | `null` | No |
| key_vault_id | Resource ID of the Key Vault that will host the certificate. | `string` | -- | Yes |
| common_name | Subject CN of the certificate. Include a wildcard if needed; also populate `dns_names`. | `string` | -- | Yes |
| organization | Subject O field (cosmetic). | `string` | `"Post Luxembourg"` | No |
| dns_names | Subject Alternative Names (DNS). Modern TLS clients verify SANs, not CN. | `list(string)` | `[]` | No |
| ip_addresses | Subject Alternative Names (IP). | `list(string)` | `[]` | No |
| validity_days | Cert validity in days. Default 365 (1 year). Range: 1-3650. | `number` | `365` | No |
| early_renewal_hours | Hours before expiry to trigger renewal at next plan/apply. 0 = disabled. | `number` | `0` | No |
| key_size | RSA key size in bits. | `number` | `2048` | No |
| lock | Optional resource lock. `kind` = "CanNotDelete" or "ReadOnly". | `object` | `null` | No |
| role_assignments | Map of role assignments scoped to the certificate versionless ID. | `map(object)` | `{}` | No |
| tags | Tags applied to the Key Vault certificate object. | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| resource | Complete `azurerm_key_vault_certificate` resource object. Use for composition. |
| certificate_id | Full resource ID of the imported Key Vault certificate. |
| certificate_name | Name of the Key Vault certificate. |
| certificate_versionless_id | Versionless certificate ID (`https://<kv>.vault.azure.net/certificates/<name>`). |
| secret_versionless_id | Versionless secret URI (`https://<kv>.vault.azure.net/secrets/<name>`). Use in the AKS App Routing CSI annotation. |
| cert_pem | PEM-encoded X.509 certificate (public portion only). |
| lock_id | Resource ID of the management lock (null if not configured). |
| role_assignment_ids | Map of role assignment key => resource ID. |
