###############################################################
# MODULE: ArgoCDBootstrap - Outputs
###############################################################

output "repo_secret_name" {
  description = "Name of the Kubernetes Secret holding the repo credentials."
  value       = kubernetes_secret_v1.repo.metadata[0].name
}

output "application_name" {
  description = "Name of the Argo CD Application CRD."
  value       = var.application_name
}

output "application_repo_url" {
  description = "Repo URL the Application watches."
  value       = var.repo_url
}

output "application_path" {
  description = "Path inside the repo that the Application reconciles."
  value       = var.application_path
}

# Truth 6 (6th application post-ContainerRegistry v0.2.83): sensitive=true
# because kubernetes_secret_v1.data is sensitive in the kubernetes provider
# schema (~> 3.0) — exposing the resource without sensitive=true would leak
# the PAT to terraform plan output.
output "resource" {
  description = "The kubernetes_secret_v1 resource holding the Argo CD repository credentials. Sensitive: contains the PAT data."
  value       = kubernetes_secret_v1.repo
  sensitive   = true
}

output "application" {
  description = "The kubernetes_manifest resource for the Argo CD Application CRD. Non-sensitive — manifest contains no secret data."
  value       = kubernetes_manifest.application
}
