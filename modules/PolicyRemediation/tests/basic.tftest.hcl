# Plan-time tests for PolicyRemediation.

mock_provider "azurerm" {}

# Test 1 — RG scope happy path
run "rg_scope_happy" {
  command = plan
  variables {
    remediations = {
      "test-rg" = {
        resource_group_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
        policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/test"
      }
    }
  }
  assert {
    condition     = length(azurerm_resource_group_policy_remediation.this) == 1
    error_message = "RG-scoped remediation should plan one resource."
  }
}

# Test 2 — scope XOR validator: two scopes set
run "two_scopes_fails" {
  command = plan
  variables {
    remediations = {
      "bad" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        resource_group_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
        policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/test"
      }
    }
  }
  expect_failures = [var.remediations]
}

# Test 3 — scope XOR validator: zero scopes
run "no_scope_fails" {
  command = plan
  variables {
    remediations = {
      "bad" = {
        policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/test"
      }
    }
  }
  expect_failures = [var.remediations]
}

# Test 4 — invalid resource_discovery_mode
run "invalid_discovery_mode_fails" {
  command = plan
  variables {
    remediations = {
      "bad" = {
        subscription_id         = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_assignment_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/test"
        resource_discovery_mode = "NotARealMode"
      }
    }
  }
  expect_failures = [var.remediations]
}

# Test 5 — MG + ReEvaluateCompliance forbidden
run "mg_with_reevaluate_fails" {
  command = plan
  variables {
    remediations = {
      "bad" = {
        management_group_id     = "/providers/Microsoft.Management/managementGroups/test-mg"
        policy_assignment_id    = "/providers/Microsoft.Management/managementGroups/test-mg/providers/Microsoft.Authorization/policyAssignments/test"
        resource_discovery_mode = "ReEvaluateCompliance"
      }
    }
  }
  expect_failures = [var.remediations]
}

# Test 6 — failure_percentage out of range
run "failure_percentage_out_of_range_fails" {
  command = plan
  variables {
    remediations = {
      "bad" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/test"
        failure_percentage   = 1.5
      }
    }
  }
  expect_failures = [var.remediations]
}

# Test 7 — parallel_deployments out of range
run "parallel_deployments_out_of_range_fails" {
  command = plan
  variables {
    remediations = {
      "bad" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/test"
        parallel_deployments = 50
      }
    }
  }
  expect_failures = [var.remediations]
}
