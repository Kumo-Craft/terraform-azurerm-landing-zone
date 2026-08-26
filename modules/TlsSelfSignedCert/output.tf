###############################################################
# MODULE: TlsSelfSignedCert - Outputs
###############################################################

output "resource" {
  description = "Complete azurerm_key_vault_certificate resource object. Use this for composition — e.g. referencing the certificate in downstream modules."
  value       = azurerm_key_vault_certificate.this
  sensitive   = true
}

output "certificate_id" {
  description = "Full resource ID of the imported Key Vault certificate."
  value       = azurerm_key_vault_certificate.this.id
}

output "certificate_name" {
  description = "Name of the Key Vault certificate."
  value       = azurerm_key_vault_certificate.this.name
}

output "certificate_versionless_id" {
  description = "Versionless KV certificate ID (e.g. https://<kv>.vault.azure.net/certificates/<name>). Use this in the Ingress annotation `kubernetes.azure.com/tls-cert-keyvault-uri` so the App Routing CSI driver always pulls the latest version."
  value       = azurerm_key_vault_certificate.this.versionless_id
}

output "secret_versionless_id" {
  description = "Versionless KV SECRET URI for the cert (e.g. https://<kv>.vault.azure.net/secrets/<name>). The App Routing addon's `kubernetes.azure.com/tls-cert-keyvault-uri` annotation accepts either the certificate or the secret URI — the secret form is what the CSI driver actually fetches under the hood."
  value       = azurerm_key_vault_certificate.this.versionless_secret_id
}

output "cert_pem" {
  description = "PEM-encoded X.509 certificate (public). Safe to expose; useful for downstream consumers that need to trust the self-signed CA (e.g. kubectl --certificate-authority)."
  value       = tls_self_signed_cert.this.cert_pem
}

output "lock_id" {
  description = "Resource ID of the management lock (null if no lock configured)."
  value       = try(module.lock.ids["this"], null)
}

output "role_assignment_ids" {
  description = "Map of role assignment key => role assignment resource ID."
  value       = { for k, m in module.rbac : k => m.id }
}
