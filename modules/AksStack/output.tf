###############################################################
# MODULE: AksStack — Outputs (wrapper-style)
#
# Re-exports the child modules' outputs with stack-prefixed names
# so callers can `dependency.aks_stack.outputs.cluster_id` etc.
###############################################################

# ─── Resource Groups ─────────────────────────────────────────
output "resource_group_name" {
  description = "Cluster RG name (caller-managed)."
  value       = var.resource_group_name
}

output "kv_resource_group_name" {
  description = "RG hosting the KV + KV PE + etcd CMK. Equal to resource_group_name when var.kv_resource_group_name is null (single-RG mode)."
  value       = local.effective_kv_rg_name
}

# ─── Identities ──────────────────────────────────────────────
output "control_plane_identity" {
  description = "Control Plane User Assigned Managed Identity used by the AKS cluster."
  value = {
    id           = module.id_cp.id
    name         = module.id_cp.name
    principal_id = module.id_cp.principal_id
    client_id    = module.id_cp.client_id
  }
}

output "kubelet_identity" {
  description = "Kubelet User Assigned Managed Identity (used by node pools to pull from ACR, read KV secrets, etc.)."
  value = {
    id           = module.id_kubelet.id
    name         = module.id_kubelet.name
    principal_id = module.id_kubelet.principal_id
    client_id    = module.id_kubelet.client_id
  }
}

# ─── Key Vault + etcd CMK ────────────────────────────────────
output "key_vault_id" {
  value = module.kv.id
}

output "key_vault_name" {
  value = module.kv.name
}

output "key_vault_uri" {
  value = module.kv.vault_uri
}

output "etcd_key_id" {
  description = "Versioned KV key ID for etcd CMK."
  value       = module.etcd_key.ids["etcd"]
}

output "etcd_key_versionless_id" {
  description = "Versionless KV key ID for etcd CMK. Use this in the post-deploy `az aks update --azure-keyvault-kms-key-id` command."
  value       = module.etcd_key.versionless_ids["etcd"]
}

# ─── Key Vault Private Endpoint ──────────────────────────────
output "kv_private_endpoint_id" {
  description = "Resource ID of the Private Endpoint targeting the etcd CMK Key Vault."
  value       = module.kv_pe.ids["kv"]
}

output "kv_private_endpoint_ip" {
  description = "Private IP address of the Key Vault Private Endpoint (null until ALZ DINE Policy completes the privateDnsZoneGroup, which doesn't change the NIC IP)."
  value       = module.kv_pe.private_ip_addresses["kv"]
}

# ─── AKS cluster ─────────────────────────────────────────────
output "cluster_id" {
  value = module.aks.id
}

output "cluster_name" {
  value = module.aks.name
}

output "cluster_fqdn" {
  description = "Private FQDN of the AKS API server."
  value       = module.aks.fqdn
}

output "node_resource_group_name" {
  value = module.aks.node_resource_group
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL — feed this into Federated Identity Credentials for Workload Identity."
  value       = module.aks.oidc_issuer_url
}

output "web_app_routing_identity_principal_id" {
  description = "Principal ID of the auto-created UAMI used by the Application Routing addon (for cross-sub RBAC grants on Azure DNS zones)."
  value       = module.aks.web_app_routing_identity_principal_id
}

output "web_app_routing_identity_client_id" {
  description = "Client ID of the auto-created UAMI used by the Application Routing addon."
  value       = module.aks.web_app_routing_identity_client_id
}

# ─── Resource lock ───────────────────────────────────────────
output "aks_lock_id" {
  description = "AKS cluster lock ID (null if var.lock is null)"
  value       = module.aks.lock_id
}

# ─── Post-deploy hint ────────────────────────────────────────
output "post_deploy_az_cli_commands" {
  description = "Commands to run AFTER apply to enable KMS v2 + API Server VNet Integration (azurerm v4 limitation). The KMS step is required even when api_server_subnet_id is null if you want Private network_access on the KV."
  value = {
    enable_api_server_vnet_integration = var.api_server_subnet_id == null ? null : "az aks update --name ${module.aks.name} --resource-group ${var.resource_group_name} --enable-apiserver-vnet-integration --apiserver-subnet-id ${var.api_server_subnet_id}"
    enable_kms_private                 = "az aks update --name ${module.aks.name} --resource-group ${var.resource_group_name} --enable-azure-keyvault-kms --azure-keyvault-kms-key-id ${module.etcd_key.versionless_ids["etcd"]} --azure-keyvault-kms-key-vault-network-access Private --azure-keyvault-kms-key-vault-resource-id ${module.kv.id}"
  }
}
