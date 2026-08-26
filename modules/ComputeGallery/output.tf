###############################################################
# MODULE: ComputeGallery - Outputs
###############################################################

output "gallery_id" {
  description = "Resource ID of the Compute Gallery."
  value       = azurerm_shared_image_gallery.this.id
}

output "gallery_name" {
  description = "Name of the Compute Gallery."
  value       = azurerm_shared_image_gallery.this.name
}

output "gallery_unique_name" {
  description = "The globally unique name of the Compute Gallery (used for cross-tenant / community sharing)."
  value       = azurerm_shared_image_gallery.this.unique_name
}

output "image_definition_id" {
  description = "Resource ID of the image definition, or null when none was created (image_definition_name = null)."
  value       = one(azurerm_shared_image.this[*].id)
}

output "image_definition_name" {
  description = "Name of the image definition, or null when none was created."
  value       = one(azurerm_shared_image.this[*].name)
}
