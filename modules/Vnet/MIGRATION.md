# Vnet — Migration to azapi inline subnets

This module's inline-subnet path was refactored from `azurerm_subnet` (+ separate
`azurerm_subnet_network_security_group_association`, `_route_table_association`,
`_nat_gateway_association`) to a single `azapi_resource` per subnet, so the
subnet, NSG, route table, NAT gateway, service endpoints and delegations all
land in **one** atomic Azure API call. This is required to comply with the
Azure Policy *"Subnets must have a Network Security Group"* (Deny effect).

The schema in `var.subnets` is unchanged. **Existing callers do not need to
modify their inputs**, but the underlying resource addresses change in state.
Without a state migration, `terraform plan` will want to destroy the old
`azurerm_subnet.*` and create new `azapi_resource.subnet.*` entries — which
Azure rejects when the subnet has dependants (Bastion host, DNS Resolver,
NICs, AKS cluster, etc.).

## When you must migrate

Run the migration **before** the next `apply` of any deployment that:

1. Uses this `Vnet` module **with** `var.subnets` populated (inline subnets), AND
2. Has already been applied (`terraform state list` shows
   `module.<key>.azurerm_subnet.this[...]` entries).

If you only used the `Vnet` module for the VNet itself and created subnets via
the separate `SubnetWithNsg` module, no migration is needed.

## Procedure

Run from the affected deployment directory (e.g.
`landing-zone/platform/connectivity/network-shared`):

```powershell
# 0. Bump the Vnet module to the new commit, then re-init
terragrunt init -reconfigure

# 1. Inventory: find old subnet & association entries
$old = terragrunt state list | Where-Object {
  $_ -match '\.azurerm_subnet\.this\[' -or
  $_ -match '\.azurerm_subnet_network_security_group_association\.this\[' -or
  $_ -match '\.azurerm_subnet_route_table_association\.this\[' -or
  $_ -match '\.azurerm_subnet_nat_gateway_association\.this\['
}
$old   # review the list

# 2. For each azurerm_subnet entry, capture the Azure resource ID
$subnetEntries = $old | Where-Object { $_ -match '\.azurerm_subnet\.this\[' }
$importMap = @{}
foreach ($e in $subnetEntries) {
  $id = (terragrunt state show $e |
         Select-String '^id\s*=' |
         ForEach-Object { ($_.Line -split '"')[1] })
  if ($e -match '\["([^"]+)"\]') { $importMap[$matches[1]] = $id }
}
$importMap   # review

# 3. Remove old entries from state (resources stay in Azure)
foreach ($e in $old) { terragrunt state rm --% $e }

# 4. Re-import each subnet under the new azapi address.
#    The module path prefix is the same as the old subnet entries.
$modulePath = ($subnetEntries[0] -replace '\.azurerm_subnet\.this\[.*$', '')
foreach ($name in $importMap.Keys) {
  $newAddr = "$modulePath.azapi_resource.subnet[`"$name`"]"
  terragrunt import --% $newAddr $importMap[$name]
}

# 5. Plan — should be NO destroy/create, only minor attribute drift on imported
#    resources (azapi reads back body fields the old schema didn't expose).
#    If the plan still wants to destroy a subnet, STOP and investigate.
terragrunt plan
```

## What "minor attribute drift" looks like

After import, `terragrunt plan` will likely show updates on the `body`
attribute of each `azapi_resource.subnet[*]`:

- `serviceEndpoints` may swap from `null` to `[]` (or vice-versa)
- `privateEndpointNetworkPolicies` may default from `null` to a value
- `defaultOutboundAccess` may flip null/false

These are **safe** in-place updates — they re-state the existing Azure
configuration in the new schema. No destroy/recreate.

If you see `# azapi_resource.subnet["..."] must be replaced` or
`# azurerm_subnet.this["..."] will be destroyed`, the migration was incomplete
— check that step 3 cleaned all entries and step 4 imported each subnet under
the correct module path.

## Rollback

If something goes wrong after step 3 but before step 5, you can re-import the
old `azurerm_subnet` addresses and revert the module to its previous commit:

```powershell
foreach ($name in $importMap.Keys) {
  $oldAddr = "$modulePath.azurerm_subnet.this[`"$name`"]"
  terragrunt import --% $oldAddr $importMap[$name]
}
# Then revert the module bump in modules/ submodule
```
