# Plan-time tests for the RbacAssignments module.
#
# Mock both providers so plan can resolve without a live Entra tenant
# or Azure subscription. The azuread_group data source is mocked with
# a stable object_id so dispatch logic can be asserted deterministically.
#
# Run with:
#   cd modules/RbacAssignments
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}

mock_provider "azuread" {
  mock_data "azuread_group" {
    defaults = {
      object_id = "00000000-0000-0000-0000-000000000001"
    }
  }
}

###############################################################
# Test 1: Smoke — group assignment with role NAME dispatches to
# role_definition_name; principal_type is hardcoded to "Group".
###############################################################
run "group_assignment_by_role_name" {
  command = plan

  variables {
    group_assignments = {
      readers = {
        group_name                 = "readers-group"
        scope                      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        role_definition_id_or_name = "Reader"
      }
    }
  }

  assert {
    condition     = azurerm_role_assignment.groups["readers"].role_definition_name == "Reader"
    error_message = "Bare role name must dispatch to role_definition_name."
  }

  assert {
    condition     = azurerm_role_assignment.groups["readers"].principal_type == "Group"
    error_message = "Group assignments must always set principal_type = Group (UnmatchedPrincipalType regression)."
  }
}

###############################################################
# Test 2: Smoke — identity assignment with role definition GUID
# path dispatches to role_definition_id; role_definition_name null.
###############################################################
run "identity_assignment_by_role_definition_id" {
  command = plan

  variables {
    identity_assignments = {
      mi_contributor = {
        principal_id               = "11111111-1111-1111-1111-111111111111"
        scope                      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        role_definition_id_or_name = "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
        principal_type             = "ServicePrincipal"
      }
    }
  }

  assert {
    condition     = azurerm_role_assignment.identities["mi_contributor"].role_definition_id == "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
    error_message = "A full roleDefinitions path must dispatch to role_definition_id."
  }
}

###############################################################
# Test 3: F1 regression — principal_type validator restricts the
# enum to 3 values. ForeignGroup must be rejected.
###############################################################
run "principal_type_foreigngroup_fails" {
  command = plan

  variables {
    identity_assignments = {
      cross_tenant = {
        principal_id               = "22222222-2222-2222-2222-222222222222"
        scope                      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        role_definition_id_or_name = "Reader"
        principal_type             = "ForeignGroup"
      }
    }
  }

  expect_failures = [var.identity_assignments]
}

###############################################################
# Test 4: F2 regression — management-group scope is accepted on
# both assignment maps (broadened in commit 2a20e72).
###############################################################
run "management_group_scope_accepted" {
  command = plan

  variables {
    group_assignments = {
      mg_reader = {
        group_name                 = "platform-admins"
        scope                      = "/providers/Microsoft.Management/managementGroups/contoso-root"
        role_definition_id_or_name = "Reader"
      }
    }
    identity_assignments = {
      mg_contrib = {
        principal_id               = "33333333-3333-3333-3333-333333333333"
        scope                      = "/providers/Microsoft.Management/managementGroups/contoso-platform"
        role_definition_id_or_name = "Contributor"
        principal_type             = "ServicePrincipal"
      }
    }
  }

  assert {
    condition     = azurerm_role_assignment.groups["mg_reader"].scope == "/providers/Microsoft.Management/managementGroups/contoso-root"
    error_message = "Management-group scope must be accepted for group assignments."
  }

  assert {
    condition     = azurerm_role_assignment.identities["mg_contrib"].scope == "/providers/Microsoft.Management/managementGroups/contoso-platform"
    error_message = "Management-group scope must be accepted for identity assignments."
  }
}

###############################################################
# Test 5: F2 regression — garbage scope must still be rejected.
###############################################################
run "invalid_scope_fails" {
  command = plan

  variables {
    group_assignments = {
      bad = {
        group_name                 = "x"
        scope                      = "not-a-valid-scope"
        role_definition_id_or_name = "Reader"
      }
    }
  }

  expect_failures = [var.group_assignments]
}

###############################################################
# Test 6: F4 regression — condition without condition_version
# must fail the co-presence validator (group_assignments side).
###############################################################
run "condition_without_version_fails_groups" {
  command = plan

  variables {
    group_assignments = {
      partial = {
        group_name                 = "x"
        scope                      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        role_definition_id_or_name = "Reader"
        condition                  = "@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringEquals 'public'"
        # condition_version intentionally omitted
      }
    }
  }

  expect_failures = [var.group_assignments]
}

###############################################################
# Test 7: F4 regression — same on the identity_assignments side,
# this time setting condition_version without condition.
###############################################################
run "version_without_condition_fails_identities" {
  command = plan

  variables {
    identity_assignments = {
      partial = {
        principal_id               = "44444444-4444-4444-4444-444444444444"
        scope                      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        role_definition_id_or_name = "Reader"
        condition_version          = "2.0"
        # condition intentionally omitted
      }
    }
  }

  expect_failures = [var.identity_assignments]
}

###############################################################
# Test 8: F9 — delegated_managed_identity_resource_id wires
# through to the resource for cross-tenant assignments.
###############################################################
run "delegated_managed_identity_passthrough" {
  command = plan

  variables {
    identity_assignments = {
      cross_tenant_mi = {
        principal_id                           = "55555555-5555-5555-5555-555555555555"
        scope                                  = "/subscriptions/00000000-0000-0000-0000-000000000000"
        role_definition_id_or_name             = "Key Vault Secrets User"
        principal_type                         = "ServicePrincipal"
        skip_service_principal_aad_check       = true
        delegated_managed_identity_resource_id = "/subscriptions/aaaa/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/cross-tenant-mi"
      }
    }
  }

  assert {
    condition     = azurerm_role_assignment.identities["cross_tenant_mi"].delegated_managed_identity_resource_id == "/subscriptions/aaaa/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/cross-tenant-mi"
    error_message = "delegated_managed_identity_resource_id must be passed through to azurerm_role_assignment."
  }
}

###############################################################
# Test 10: NF-2 regression — condition_version "3.0" must be
# rejected by the enum validator on group_assignments.
# Both condition and condition_version are supplied to satisfy
# the F4 co-presence check; the enum validator fires second.
###############################################################
run "invalid_condition_version_fails_groups" {
  command = plan

  variables {
    group_assignments = {
      bad_version = {
        group_name                 = "x"
        scope                      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        role_definition_id_or_name = "Reader"
        condition                  = "@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringEquals 'public'"
        condition_version          = "3.0"
      }
    }
  }

  expect_failures = [var.group_assignments]
}

###############################################################
# Test 11: NF-2 symmetric — condition_version "3.0" must be
# rejected by the enum validator on identity_assignments.
# Both condition and condition_version are supplied to satisfy
# the F4 co-presence check; the enum validator fires second.
###############################################################
run "invalid_condition_version_fails_identities" {
  command = plan

  variables {
    identity_assignments = {
      bad_version = {
        principal_id               = "44444444-4444-4444-4444-444444444444"
        scope                      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        role_definition_id_or_name = "Reader"
        condition                  = "@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringEquals 'public'"
        condition_version          = "3.0"
      }
    }
  }

  expect_failures = [var.identity_assignments]
}

###############################################################
# Test 9: Empty maps — default behaviour yields zero resources
# (sanity: module is safe to declare without inputs).
###############################################################
run "empty_inputs_yield_no_resources" {
  command = plan

  variables {
    group_assignments    = {}
    identity_assignments = {}
  }

  assert {
    condition     = length(azurerm_role_assignment.groups) == 0
    error_message = "Empty group_assignments must produce 0 group role assignments."
  }

  assert {
    condition     = length(azurerm_role_assignment.identities) == 0
    error_message = "Empty identity_assignments must produce 0 identity role assignments."
  }
}
