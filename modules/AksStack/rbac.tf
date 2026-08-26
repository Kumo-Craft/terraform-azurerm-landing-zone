###############################################################
# MODULE: AksStack — RBAC role assignments
#
# All role assignments delegated to ../RoleAssignment (canonical
# single-grant module). Sprint 7 P0 #1 reversed: now that
# RoleAssignment exists, composition replaces inline duplication.
#
#   1. Kubelet UAMI → Key Vault Crypto User on the etcd KV.
#   2. CP UAMI → Network Contributor on the node subnet (required
#      before AKS create — depends_on guard in main.tf).
#   3. Kubelet UAMI → AcrPull on each ACR in var.acr_pull_target_ids.
#   4. Optional caller-provided cluster admin / user role grants
#      (Azure RBAC for Kubernetes API).
###############################################################

###############################################################
# RBAC #1: Kubelet UAMI → Key Vault Crypto User (for etcd CMK)
###############################################################
module "kubelet_kv_crypto_user" {
  source = "../RoleAssignment"

  scope                = module.kv.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = module.id_kubelet.principal_id
  principal_type       = "ServicePrincipal"
}

moved {
  from = azurerm_role_assignment.kubelet_kv_crypto_user
  to   = module.kubelet_kv_crypto_user.azurerm_role_assignment.this
}

###############################################################
# RBAC #1b: CP UAMI → Managed Identity Operator on kubelet UAMI
#
# Required when control-plane and kubelet identities are separate
# UAMIs (our pattern). The control plane needs this role to assign
# the kubelet UAMI to VMSS instances at scale-out / upgrade time.
#
# Without this, AKS create fails with:
#   CustomKubeletIdentityMissingPermissionError
###############################################################
module "cp_kubelet_mi_operator" {
  source = "../RoleAssignment"

  scope                = module.id_kubelet.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = module.id_cp.principal_id
  principal_type       = "ServicePrincipal"
}

moved {
  from = azurerm_role_assignment.cp_kubelet_mi_operator
  to   = module.cp_kubelet_mi_operator.azurerm_role_assignment.this
}

###############################################################
# RBAC #1c: CP UAMI → Key Vault Contributor on the etcd KV
#
# Required when KMS Private is enabled. AKS creates an AKS-managed
# Private Endpoint in the AKS-managed node RG that connects to the
# KV's private link service. The CP UAMI initiates this connection
# and needs Microsoft.KeyVault/vaults/PrivateEndpointConnectionsApproval/action
# on the KV to approve the PE connection from the AKS side.
#
# Without this, az aks update --enable-azure-keyvault-kms fails with:
#   LinkedAuthorizationFailed: ... PrivateEndpointConnectionsApproval/action
# and the cluster lands in provisioningState=Failed even though the
# KMS config is partially applied.
#
# Built-in role chosen: "Key Vault Contributor" (includes the action;
# scoped to the KV resource only — minimal blast radius). A custom role
# with just PrivateEndpointConnectionsApproval/action would be tighter
# but adds management overhead — refactor opportunity for Sprint 9.
###############################################################
module "cp_kv_contributor" {
  source = "../RoleAssignment"
  count  = var.kms_v2_enabled ? 1 : 0

  scope                = module.kv.id
  role_definition_name = "Key Vault Contributor"
  principal_id         = module.id_cp.principal_id
  principal_type       = "ServicePrincipal"
}

moved {
  from = azurerm_role_assignment.cp_kv_contributor
  to   = module.cp_kv_contributor[0].azurerm_role_assignment.this
}

###############################################################
# RBAC #1d: CP UAMI → Key Vault Crypto User on the etcd KV
#
# Required when KMS Private is enabled (the AKS kms-plugin in
# private mode runs as the *cluster identity*, not the kubelet).
# It needs Wrap / Unwrap on the etcd CMK to encrypt and decrypt
# the etcd data-encryption keys.
#
# Microsoft docs (use-kms-etcd-encryption.md, "Grant access" section):
#   - Public mode  → kubelet identity needs Wrap/Unwrap (covered by
#                    RBAC #1 above, "kubelet_kv_crypto_user").
#   - Private mode → cluster (CP) identity needs Wrap/Unwrap.
#
# We keep BOTH (kubelet + CP) on Crypto User. Cost is zero (RBAC
# assignments are free, no data-plane traffic) and it makes the
# cluster mode-agnostic — switching public ↔ private requires no
# RBAC change.
#
# Without this on private mode, etcd basic enc/dec keeps working
# off the cached DEK but periodic key rotation and reconnects
# silently fail until the cache expires, after which etcd writes
# start returning errors. Validated against the apimanager AKS
# setup (landing-zone/corporate/apimanager/rbac-api/ already grants
# this role via `cluster_kv_crypto_user`).
###############################################################
module "cp_kv_crypto_user" {
  source = "../RoleAssignment"
  count  = var.kms_v2_enabled ? 1 : 0

  scope                = module.kv.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = module.id_cp.principal_id
  principal_type       = "ServicePrincipal"
}

moved {
  from = azurerm_role_assignment.cp_kv_crypto_user
  to   = module.cp_kv_crypto_user[0].azurerm_role_assignment.this
}

###############################################################
# RBAC #2: CP UAMI → Network Contributor on node subnet
#
# Required so AKS can create the load balancer NICs, attach the
# node NICs to the subnet, and manage subnet-level config on
# behalf of the cluster.
###############################################################
module "cp_subnet_network_contrib" {
  source = "../RoleAssignment"

  scope                = var.node_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = module.id_cp.principal_id
  principal_type       = "ServicePrincipal"
}

moved {
  from = azurerm_role_assignment.cp_subnet_network_contrib
  to   = module.cp_subnet_network_contrib.azurerm_role_assignment.this
}

###############################################################
# RBAC #2b: CP UAMI → Network Contributor on apiserver subnet
#
# When VNet integration is enabled (kv_pe_subnet_id implies it via the
# Aks module's post-create az aks update), AKS injects the apiserver
# NICs into the apiserver subnet. The CP UAMI needs the
# Microsoft.Network/virtualNetworks/subnets/joinLoadBalancer/action perm,
# which Network Contributor grants.
#
# Without this, az aks update --enable-apiserver-vnet-integration fails
# with ResourceMissingPermissionError on joinLoadBalancer/action.
###############################################################
module "cp_apiserver_subnet_network_contrib" {
  source = "../RoleAssignment"
  count  = var.api_server_subnet_id != null ? 1 : 0

  scope                = var.api_server_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = module.id_cp.principal_id
  principal_type       = "ServicePrincipal"
}

moved {
  from = azurerm_role_assignment.cp_apiserver_subnet_network_contrib
  to   = module.cp_apiserver_subnet_network_contrib[0].azurerm_role_assignment.this
}

###############################################################
# RBAC #3: Kubelet UAMI → AcrPull on each ACR
###############################################################
module "kubelet_acr_pull" {
  source   = "../RoleAssignment"
  for_each = toset(var.acr_pull_target_ids)

  scope                = each.value
  role_definition_name = "AcrPull"
  principal_id         = module.id_kubelet.principal_id
  principal_type       = "ServicePrincipal"
}

###############################################################
# RBAC #4a: Cluster Admin (caller-provided)
###############################################################
module "cluster_admin" {
  source   = "../RoleAssignment"
  for_each = toset(var.cluster_admin_principal_ids)

  scope                = module.aks.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
  # AKS admin/user grants target Entra GROUPS (AAD-integrated RBAC), not SPNs.
  # Without this the RoleAssignment default ("ServicePrincipal") makes Azure
  # reject a Group principal with 400 UnmatchedPrincipalType.
  principal_type = "Group"
}

###############################################################
# RBAC #4b: Cluster User (caller-provided — kubectl exec/logs)
###############################################################
module "cluster_user" {
  source   = "../RoleAssignment"
  for_each = toset(var.cluster_user_principal_ids)

  scope                = module.aks.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = each.value
  # Entra GROUPS (AAD-integrated RBAC) — see cluster_admin above.
  principal_type = "Group"
}
