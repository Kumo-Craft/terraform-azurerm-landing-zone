###############################################################
# MODULE: StorageAccountStack - Outputs
###############################################################

output "id" {
  description = "Storage Account ID"
  value       = module.storage.id
}

output "name" {
  description = "Storage Account name"
  value       = module.storage.name
}

output "primary_blob_endpoint" {
  description = "Primary blob endpoint URL"
  value       = module.storage.primary_blob_endpoint
}

output "primary_file_endpoint" {
  description = "Primary Azure Files endpoint URL"
  value       = module.storage.primary_file_endpoint
}

output "primary_access_key" {
  description = "Primary access key (empty when shared_access_key_enabled = false)"
  value       = module.storage.primary_access_key
  sensitive   = true
}

output "containers" {
  description = "Map of container key => { id, name }"
  value       = module.storage.containers
}

output "file_shares" {
  description = "Map of file share key => { id, name, url }"
  value       = module.storage.file_shares
}

output "private_endpoint_ids" {
  description = "Map of Storage sub-resource => Private Endpoint resource ID."
  value       = { for sr, m in module.pe : sr => m.ids["this"] }
}

output "private_endpoint_ip_addresses" {
  description = "Map of Storage sub-resource => Private Endpoint private IP address."
  value       = { for sr, m in module.pe : sr => m.private_ip_addresses["this"] }
}
