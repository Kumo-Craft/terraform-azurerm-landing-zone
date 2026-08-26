# Plan-time tests for the PaloCluster module.
#
# Mocks azurerm + time + random. Covers:
#   - Convention naming (slug "lb" from Azure/naming/azurerm v0.4.3, "-trust" suffix)
#   - Name override escape hatch (byte-for-byte preservation)
#   - Invalid subscription_acronym regex (fails on var.subscription_acronym)
#   - Multi-firewall (HA pair) — NIC + VM count assertions
#   - Workload-too-long validator (fires after stripping "palo-" prefix)
#   - Invalid lock.kind enum (fails on var.lock)
#   - With disk encryption — module.kv count + azurerm_key_vault_key.des count
#   - Without disk encryption — module.kv count == 0
#   - accept_marketplace_agreement gating (true → resource created, false → 0)
#
# Run with:
#   cd modules/PaloCluster
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}
mock_provider "random" {}

# Shared minimal inputs reused across all happy-path tests.
# var.firewalls uses: mgmt_ip, untrust_ip, trust_ip (and optional zone).
# var.admin_password satisfies the "at least one auth credential" validator.
# enable_disk_encryption = false keeps most tests lean (no KV/key/DES/UAI).

# ---------------------------------------------------------------------
# Test 1: Convention naming happy path.
#   All 4 naming vars provided, var.name = null.
#   The ../Naming submodule wraps Azure/naming/azurerm v0.4.3; the "lb"
#   resource type uses slug "lb" which produces prefix "lb-".
#   PaloCluster appends "-trust" → expected: "lb-con-prod-gwc-palo-net-trust".
# ---------------------------------------------------------------------
run "convention_naming_happy" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "palo-net"
    location             = "germanywestcentral"
    resource_group_name  = "rg-palo-test"

    subnet_mgmt_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-mgmt"
    subnet_trust_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-trust"
    subnet_untrust_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-untrust"
    ilb_frontend_ip   = "10.0.0.10"

    firewalls = {
      "fw-01" = {
        mgmt_ip    = "10.0.1.10"
        untrust_ip = "10.0.3.10"
        trust_ip   = "10.0.2.10"
        zone       = "1"
      }
    }

    admin_password         = "Test-Password-1234!"
    enable_disk_encryption = false
  }

  assert {
    condition     = azurerm_lb.trust.name == "lb-con-prod-gwc-palo-net-trust"
    error_message = "Convention naming must produce lb-{acr}-{env}-{region}-{workload}-trust (slug is 'lb' in Azure/naming/azurerm v0.4.3)."
  }
}

# ---------------------------------------------------------------------
# Test 2: Name override — var.name wins (byte-for-byte preservation).
#   Callers upgrading from legacy "ilb-..." names use this to suppress rename.
#   subscription_acronym/environment/region_code/workload are nullable=false
#   with no default so they must always be supplied; they are unused here
#   because var.name != null skips the module.naming for_each.
# ---------------------------------------------------------------------
run "name_override_happy" {
  command = plan

  variables {
    name                 = "ilb-legacy-name"
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "palo-net"
    location             = "germanywestcentral"
    resource_group_name  = "rg-palo-test"

    subnet_mgmt_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-mgmt"
    subnet_trust_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-trust"
    subnet_untrust_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-untrust"
    ilb_frontend_ip   = "10.0.0.10"

    firewalls = {
      "fw-01" = {
        mgmt_ip    = "10.0.1.10"
        untrust_ip = "10.0.3.10"
        trust_ip   = "10.0.2.10"
        zone       = "1"
      }
    }

    admin_password         = "Test-Password-1234!"
    enable_disk_encryption = false
  }

  assert {
    condition     = azurerm_lb.trust.name == "ilb-legacy-name"
    error_message = "Explicit var.name must be preserved byte-for-byte as the ILB name."
  }
}

# ---------------------------------------------------------------------
# Test 3: Naming var regex validator — subscription_acronym contains
#   digits (not pure lowercase letters). The var.subscription_acronym
#   validation requires ^[a-z]{2,5}$; "con123" fails it.
#   Note: the XOR validator on var.name cannot be triggered via test
#   inputs because subscription_acronym/environment/region_code/workload
#   are nullable=false with no defaults — Terraform enforces them before
#   any custom validation runs. The regex validators are the next-best proxy.
# ---------------------------------------------------------------------
run "invalid_subscription_acronym_fails" {
  command = plan

  variables {
    subscription_acronym = "con123"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "palo-net"
    location             = "germanywestcentral"
    resource_group_name  = "rg-palo-test"

    subnet_mgmt_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-mgmt"
    subnet_trust_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-trust"
    subnet_untrust_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-untrust"
    ilb_frontend_ip   = "10.0.0.10"

    firewalls = {
      "fw-01" = {
        mgmt_ip    = "10.0.1.10"
        untrust_ip = "10.0.3.10"
        trust_ip   = "10.0.2.10"
        zone       = "1"
      }
    }

    admin_password         = "Test-Password-1234!"
    enable_disk_encryption = false
  }

  expect_failures = [var.subscription_acronym]
}

# ---------------------------------------------------------------------
# Test 4: Multi-firewall HA pair — 2 entries in var.firewalls.
#   Verifies VM count and management NIC count are both 2.
# ---------------------------------------------------------------------
run "multi_firewall_happy" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "palo-net"
    location             = "germanywestcentral"
    resource_group_name  = "rg-palo-test"

    subnet_mgmt_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-mgmt"
    subnet_trust_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-trust"
    subnet_untrust_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-untrust"
    ilb_frontend_ip   = "10.0.0.10"

    firewalls = {
      "fw-01" = {
        mgmt_ip    = "10.0.1.10"
        untrust_ip = "10.0.3.10"
        trust_ip   = "10.0.2.10"
        zone       = "1"
      }
      "fw-02" = {
        mgmt_ip    = "10.0.1.11"
        untrust_ip = "10.0.3.11"
        trust_ip   = "10.0.2.11"
        zone       = "2"
      }
    }

    admin_password         = "Test-Password-1234!"
    enable_disk_encryption = false
  }

  assert {
    condition     = length(azurerm_linux_virtual_machine.this) == 2
    error_message = "Two entries in var.firewalls must produce exactly two azurerm_linux_virtual_machine resources."
  }

  assert {
    condition     = length(azurerm_network_interface.mgmt) == 2
    error_message = "Two entries in var.firewalls must produce exactly two management NICs."
  }
}

# ---------------------------------------------------------------------
# Test 5: Workload too long validator.
#   After stripping "palo-" prefix, the remaining segment must be <= 8 chars
#   (to keep the Key Vault name within Azure's 24-char limit).
#   "palo-thislong" → "thislong" (8 chars) is the boundary;
#   "palo-toolongwl" → "toolongwl" (9 chars) must fail.
# ---------------------------------------------------------------------
run "invalid_workload_too_long_fails" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "palo-toolongwl"
    location             = "germanywestcentral"
    resource_group_name  = "rg-palo-test"

    subnet_mgmt_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-mgmt"
    subnet_trust_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-trust"
    subnet_untrust_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-untrust"
    ilb_frontend_ip   = "10.0.0.10"

    firewalls = {
      "fw-01" = {
        mgmt_ip    = "10.0.1.10"
        untrust_ip = "10.0.3.10"
        trust_ip   = "10.0.2.10"
        zone       = "1"
      }
    }

    admin_password         = "Test-Password-1234!"
    enable_disk_encryption = false
  }

  expect_failures = [var.workload]
}

# ---------------------------------------------------------------------
# Test 6: Invalid lock.kind enum.
#   var.lock.kind must be "CanNotDelete" or "ReadOnly".
#   Validator is declared on var.lock.
# ---------------------------------------------------------------------
run "invalid_lock_kind_fails" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "palo-net"
    location             = "germanywestcentral"
    resource_group_name  = "rg-palo-test"

    subnet_mgmt_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-mgmt"
    subnet_trust_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-trust"
    subnet_untrust_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-untrust"
    ilb_frontend_ip   = "10.0.0.10"

    firewalls = {
      "fw-01" = {
        mgmt_ip    = "10.0.1.10"
        untrust_ip = "10.0.3.10"
        trust_ip   = "10.0.2.10"
        zone       = "1"
      }
    }

    admin_password         = "Test-Password-1234!"
    enable_disk_encryption = false

    lock = {
      kind = "InvalidKind"
    }
  }

  expect_failures = [var.lock]
}

# ---------------------------------------------------------------------
# Test 7: With disk encryption — KV module + DES key both created.
#   enable_disk_encryption = true gates module.kv (count=1) and
#   azurerm_key_vault_key.des (count=1).
#   override_data supplies a valid UUID for tenant_id because the
#   composed ../KeyVault module calls data.azurerm_client_config.current
#   and the mock provider returns a random non-UUID string by default.
# ---------------------------------------------------------------------
run "with_disk_encryption_happy" {
  command = plan

  override_data {
    target = module.kv[0].data.azurerm_client_config.current
    values = {
      tenant_id = "00000000-0000-0000-0000-000000000002"
    }
  }

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "palo-net"
    location             = "germanywestcentral"
    resource_group_name  = "rg-palo-test"

    subnet_mgmt_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-mgmt"
    subnet_trust_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-trust"
    subnet_untrust_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-untrust"
    ilb_frontend_ip   = "10.0.0.10"

    firewalls = {
      "fw-01" = {
        mgmt_ip    = "10.0.1.10"
        untrust_ip = "10.0.3.10"
        trust_ip   = "10.0.2.10"
        zone       = "1"
      }
    }

    enable_disk_encryption = true
    kv_admin_principal_ids = ["00000000-0000-0000-0000-000000000001"]
  }

  assert {
    condition     = length(module.kv) == 1
    error_message = "enable_disk_encryption = true must compose exactly one module.kv instance."
  }

  assert {
    condition     = length(azurerm_key_vault_key.des) == 1
    error_message = "enable_disk_encryption = true must create exactly one azurerm_key_vault_key.des."
  }

  # CKV_AZURE_40: the DES key expiration anchor must be created so the key
  # receives an expiration_date. (Value is computed at apply; assert on count,
  # which is known at plan.)
  assert {
    condition     = length(time_offset.des_key_expiry) == 1
    error_message = "enable_disk_encryption = true must create exactly one time_offset.des_key_expiry (drives the key expiration_date)."
  }
}

# ---------------------------------------------------------------------
# Test 8: Without disk encryption — KV module + DES key both absent.
#   enable_disk_encryption = false → module.kv count == 0,
#   azurerm_key_vault_key.des count == 0.
# ---------------------------------------------------------------------
run "without_disk_encryption_happy" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "palo-net"
    location             = "germanywestcentral"
    resource_group_name  = "rg-palo-test"

    subnet_mgmt_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-mgmt"
    subnet_trust_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-trust"
    subnet_untrust_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-untrust"
    ilb_frontend_ip   = "10.0.0.10"

    firewalls = {
      "fw-01" = {
        mgmt_ip    = "10.0.1.10"
        untrust_ip = "10.0.3.10"
        trust_ip   = "10.0.2.10"
        zone       = "1"
      }
    }

    admin_password         = "Test-Password-1234!"
    enable_disk_encryption = false
  }

  assert {
    condition     = length(module.kv) == 0
    error_message = "enable_disk_encryption = false must produce zero module.kv instances."
  }

  assert {
    condition     = length(azurerm_key_vault_key.des) == 0
    error_message = "enable_disk_encryption = false must produce zero azurerm_key_vault_key.des resources."
  }

  assert {
    condition     = length(time_offset.des_key_expiry) == 0
    error_message = "enable_disk_encryption = false must produce zero time_offset.des_key_expiry resources."
  }
}

# ---------------------------------------------------------------------
# Test 8b: vwan BGP secrets carry an expiration anchor (CKV_AZURE_41).
#   enable_disk_encryption = true + vwan vars set → both secrets are
#   created and exactly one time_offset.vwan_secret_expiry drives their
#   expiration_date. (Values computed at apply; assert on counts.)
# ---------------------------------------------------------------------
run "vwan_secrets_have_expiration_anchor" {
  command = plan

  override_data {
    target = module.kv[0].data.azurerm_client_config.current
    values = {
      tenant_id = "00000000-0000-0000-0000-000000000002"
    }
  }

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "palo-net"
    location             = "germanywestcentral"
    resource_group_name  = "rg-palo-test"

    subnet_mgmt_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-mgmt"
    subnet_trust_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-trust"
    subnet_untrust_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-untrust"
    ilb_frontend_ip   = "10.0.0.10"

    firewalls = {
      "fw-01" = {
        mgmt_ip    = "10.0.1.10"
        untrust_ip = "10.0.3.10"
        trust_ip   = "10.0.2.10"
        zone       = "1"
      }
    }

    enable_disk_encryption = true
    kv_admin_principal_ids = ["00000000-0000-0000-0000-000000000001"]
    vwan_bgp_peer_ips      = ["10.0.0.4", "10.0.0.5"]
    vwan_bgp_peer_asn      = 65515
  }

  assert {
    condition     = length(azurerm_key_vault_secret.vwan_bgp_peer_ips) == 1 && length(azurerm_key_vault_secret.vwan_bgp_peer_asn) == 1
    error_message = "Both vwan BGP secrets must be created when the vwan vars are set."
  }

  assert {
    condition     = length(time_offset.vwan_secret_expiry) == 1
    error_message = "Exactly one time_offset.vwan_secret_expiry must drive the vwan secrets' expiration_date."
  }
}

# ---------------------------------------------------------------------
# Test 9a: accept_marketplace_agreement = true → resource created.
# Test 9b: accept_marketplace_agreement = false (default) → resource absent.
# ---------------------------------------------------------------------
run "accept_marketplace_agreement_creates_resource" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "palo-net"
    location             = "germanywestcentral"
    resource_group_name  = "rg-palo-test"

    subnet_mgmt_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-mgmt"
    subnet_trust_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-trust"
    subnet_untrust_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-untrust"
    ilb_frontend_ip   = "10.0.0.10"

    firewalls = {
      "fw-01" = {
        mgmt_ip    = "10.0.1.10"
        untrust_ip = "10.0.3.10"
        trust_ip   = "10.0.2.10"
        zone       = "1"
      }
    }

    admin_password               = "Test-Password-1234!"
    enable_disk_encryption       = false
    accept_marketplace_agreement = true
  }

  assert {
    condition     = length(azurerm_marketplace_agreement.palo) == 1
    error_message = "accept_marketplace_agreement = true must create exactly one azurerm_marketplace_agreement resource."
  }
}

run "no_marketplace_agreement_when_false" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "palo-net"
    location             = "germanywestcentral"
    resource_group_name  = "rg-palo-test"

    subnet_mgmt_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-mgmt"
    subnet_trust_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-trust"
    subnet_untrust_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-untrust"
    ilb_frontend_ip   = "10.0.0.10"

    firewalls = {
      "fw-01" = {
        mgmt_ip    = "10.0.1.10"
        untrust_ip = "10.0.3.10"
        trust_ip   = "10.0.2.10"
        zone       = "1"
      }
    }

    admin_password               = "Test-Password-1234!"
    enable_disk_encryption       = false
    accept_marketplace_agreement = false
  }

  assert {
    condition     = length(azurerm_marketplace_agreement.palo) == 0
    error_message = "accept_marketplace_agreement = false must produce zero azurerm_marketplace_agreement resources."
  }
}

# ---------------------------------------------------------------------
# Test 11: XOR auth validator — no admin_password, no SSH key,
#   enable_disk_encryption = false. The validator on var.admin_password
#   fires: "Either admin_password, admin_ssh_public_key, or
#   enable_disk_encryption (for auto-generated password stored in KV)
#   must be set."
# ---------------------------------------------------------------------
run "no_auth_method_fails" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "palo-net"
    location             = "germanywestcentral"
    resource_group_name  = "rg-palo-test"

    subnet_mgmt_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-mgmt"
    subnet_trust_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-trust"
    subnet_untrust_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-untrust"
    ilb_frontend_ip   = "10.0.0.10"

    firewalls = {
      "fw-01" = {
        mgmt_ip    = "10.0.1.10"
        untrust_ip = "10.0.3.10"
        trust_ip   = "10.0.2.10"
        zone       = "1"
      }
    }

    # admin_password omitted (null), admin_ssh_public_key omitted (null),
    # enable_disk_encryption = false → no auth method → validator must fail.
    enable_disk_encryption = false
  }

  expect_failures = [var.admin_password]
}
