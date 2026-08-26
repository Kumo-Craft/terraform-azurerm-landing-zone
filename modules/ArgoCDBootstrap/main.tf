###############################################################
# MODULE: ArgoCDBootstrap - Main
###############################################################

###############################################################
# Argo CD repository Secret
#
# Argo CD discovers repository connections by scanning Secrets in
# its namespace with the label
# `argocd.argoproj.io/secret-type: repository`. The secret carries
# the connection params (type, url, username, password/PAT).
###############################################################
resource "kubernetes_secret_v1" "repo" {
  metadata {
    name      = var.repo_secret_name
    namespace = var.argocd_namespace

    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  type = "Opaque"

  data = {
    type     = "git"
    url      = var.repo_url
    username = var.repo_username
    password = var.repo_pat
  }
}

###############################################################
# Argo CD Application CRD
#
# Declared as a kubernetes_manifest so we don't depend on the
# argocd Terraform provider.
#
# IMPORTANT — CRD pre-existence requirement:
#
#   The kubernetes provider resolves the OpenAPI schema of
#   argoproj.io/v1alpha1/Application at PLAN TIME, not just at
#   apply time. This means:
#
#   1. Argo CD MUST be fully installed in the target AKS cluster
#      BEFORE running `terraform plan` against this module.
#      If the CRD does not exist yet, the plan will fail with
#      a "failed to get schema information" or "no resource type"
#      error from the kubernetes provider.
#
#   2. The `depends_on` block below (Secret -> manifest) only
#      controls intra-module ordering. It does NOT ensure that
#      Argo CD is installed before this module is planned —
#      that is the caller's responsibility.
#
#   3. Recommended caller pattern (Terragrunt):
#      - Deploy Argo CD first (AKS add-on, a separate
#        helm_release module, or manual `kubectl apply -f`).
#      - Only after Argo CD pods are running and CRDs are
#        registered, plan/apply this ArgoCDBootstrap module.
#
###############################################################
resource "kubernetes_manifest" "application" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"

    metadata = {
      name      = var.application_name
      namespace = var.argocd_namespace
    }

    spec = {
      project = var.argocd_project

      source = {
        repoURL        = var.repo_url
        targetRevision = var.application_target_revision
        path           = var.application_path

        directory = {
          recurse = var.directory_recurse
        }
      }

      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.destination_namespace
      }

      syncPolicy = {
        automated = {
          prune    = var.sync_policy_prune
          selfHeal = var.sync_policy_self_heal
        }

        syncOptions = [
          "CreateNamespace=true",
        ]
      }
    }
  }

  depends_on = [
    kubernetes_secret_v1.repo,
  ]
}
