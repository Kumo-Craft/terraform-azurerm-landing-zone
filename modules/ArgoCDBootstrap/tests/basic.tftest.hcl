# Plan-time tests for the ArgoCDBootstrap module.
#
# Mocks the kubernetes provider (~> 3.0). Covers:
#   1.  happy_plan              — secret metadata, labels, type, manifest kind/apiVersion,
#                                 project, destination, sync policy (F-3 / Truth 12)
#   2.  happy_custom_project    — var.argocd_project wires through to manifest (F-8)
#   3.  happy_custom_namespace  — var.argocd_namespace applied to both resources
#   4.  happy_prune_disabled    — sync_policy_prune=false reflects in manifest
#   5.  happy_no_recurse        — directory_recurse=false reflects in manifest
#   6.  validator_secret_name   — bad repo_secret_name regex rejected
#   7.  validator_app_name      — bad application_name regex rejected
#
# Run with:
#   cd modules/ArgoCDBootstrap
#   terraform init -backend=false
#   terraform test

mock_provider "kubernetes" {}

# Shared required inputs reused across all runs.
variables {
  repo_url = "https://dev.azure.com/myorg/myproject/_git/myrepo"
  repo_pat = "my-test-pat-value-for-plan-only"
}

# -----------------------------------------------------------------------
# Test 1: happy_plan — plan-time assertions on secret + manifest structure.
# -----------------------------------------------------------------------
run "happy_plan" {
  command = plan

  assert {
    condition     = kubernetes_secret_v1.repo.metadata[0].name == "argocd-platform-manifests-repo"
    error_message = "repo secret name must match the default var.repo_secret_name value."
  }

  assert {
    condition     = kubernetes_secret_v1.repo.metadata[0].namespace == "argocd"
    error_message = "repo secret namespace must match the default var.argocd_namespace value."
  }

  assert {
    condition     = kubernetes_secret_v1.repo.metadata[0].labels["argocd.argoproj.io/secret-type"] == "repository"
    error_message = "repo secret must carry the argocd.argoproj.io/secret-type=repository label."
  }

  assert {
    condition     = kubernetes_secret_v1.repo.type == "Opaque"
    error_message = "repo secret type must be Opaque."
  }

  assert {
    condition     = kubernetes_manifest.application.manifest.kind == "Application"
    error_message = "Application manifest kind must be 'Application'."
  }

  assert {
    condition     = kubernetes_manifest.application.manifest.apiVersion == "argoproj.io/v1alpha1"
    error_message = "Application manifest apiVersion must be 'argoproj.io/v1alpha1'."
  }

  assert {
    condition     = kubernetes_manifest.application.manifest.spec.project == "default"
    error_message = "Application manifest spec.project must default to 'default'."
  }

  assert {
    condition     = kubernetes_manifest.application.manifest.spec.destination.server == "https://kubernetes.default.svc"
    error_message = "Application manifest spec.destination.server must be the in-cluster API server address."
  }

  assert {
    condition     = kubernetes_manifest.application.manifest.spec.syncPolicy.automated.prune == true
    error_message = "sync_policy_prune must default to true."
  }

  assert {
    condition     = kubernetes_manifest.application.manifest.spec.syncPolicy.automated.selfHeal == true
    error_message = "sync_policy_self_heal must default to true."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_custom_project — var.argocd_project wires through (F-8).
# -----------------------------------------------------------------------
run "happy_custom_project" {
  command = plan

  variables {
    argocd_project = "platform-restricted"
  }

  assert {
    condition     = kubernetes_manifest.application.manifest.spec.project == "platform-restricted"
    error_message = "Application manifest spec.project must reflect var.argocd_project when overridden."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_custom_namespace — var.argocd_namespace applied to both resources.
# -----------------------------------------------------------------------
run "happy_custom_namespace" {
  command = plan

  variables {
    argocd_namespace = "argo-system"
  }

  assert {
    condition     = kubernetes_secret_v1.repo.metadata[0].namespace == "argo-system"
    error_message = "repo secret namespace must reflect var.argocd_namespace override."
  }

  assert {
    condition     = kubernetes_manifest.application.manifest.metadata.namespace == "argo-system"
    error_message = "Application manifest metadata.namespace must reflect var.argocd_namespace override."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_prune_disabled — sync_policy_prune=false reflects in manifest.
# -----------------------------------------------------------------------
run "happy_prune_disabled" {
  command = plan

  variables {
    sync_policy_prune = false
  }

  assert {
    condition     = kubernetes_manifest.application.manifest.spec.syncPolicy.automated.prune == false
    error_message = "sync_policy_prune=false must propagate to manifest spec.syncPolicy.automated.prune."
  }
}

# -----------------------------------------------------------------------
# Test 5: happy_no_recurse — directory_recurse=false reflects in manifest.
# -----------------------------------------------------------------------
run "happy_no_recurse" {
  command = plan

  variables {
    directory_recurse = false
  }

  assert {
    condition     = kubernetes_manifest.application.manifest.spec.source.directory.recurse == false
    error_message = "directory_recurse=false must propagate to manifest spec.source.directory.recurse."
  }
}

# -----------------------------------------------------------------------
# Test 6: validator_secret_name — bad repo_secret_name regex rejected.
# -----------------------------------------------------------------------
run "validator_secret_name" {
  command = plan

  variables {
    repo_secret_name = "INVALID_SECRET_NAME!"
  }

  expect_failures = [var.repo_secret_name]
}

# -----------------------------------------------------------------------
# Test 7: validator_app_name — bad application_name regex rejected.
# -----------------------------------------------------------------------
run "validator_app_name" {
  command = plan

  variables {
    application_name = "INVALID_APP_NAME!"
  }

  expect_failures = [var.application_name]
}
