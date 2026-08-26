###############################################################
# MODULE: AvdImageTemplate - Outputs
###############################################################

output "template_id" {
  description = "Resource ID of the image template."
  value       = azapi_resource.template.id
}

output "template_name" {
  description = "Name of the image template."
  value       = azapi_resource.template.name
}

output "run_output_name" {
  description = "The distribution runOutput name — query it post-build for the produced image version details."
  value       = local.run_output_name
}

output "image_definition_id" {
  description = "The Compute Gallery image definition the build distributes into (echo of input)."
  value       = var.image_definition_id
}
