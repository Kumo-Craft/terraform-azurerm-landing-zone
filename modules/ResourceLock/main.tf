###############################################################
# MODULE: ResourceLock - Main
# Description: Creates management locks on Azure resources.
#              Use enable_locks = false to disable during maintenance.
###############################################################

resource "azurerm_management_lock" "this" {
  for_each = var.enable_locks ? var.locks : {}

  name       = coalesce(each.value.name, "lock-${each.key}")
  scope      = each.value.scope
  lock_level = each.value.lock_level
  # notes is ForceNew in the provider — any edit here destroys+recreates the lock (resource briefly unprotected).
  notes = each.value.notes
}
