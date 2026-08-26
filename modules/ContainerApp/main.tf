###############################################################
# MODULE: ContainerApp - Main
# Description: Azure Container App (Microsoft.App/containerApps)
#              running on a Container Apps Environment.
###############################################################

resource "time_static" "time" {}

locals {
  # Convention name: ca-{acr}-{env}-{region}-{workload}.
  name = var.name != null ? var.name : "ca-${var.subscription_acronym}-${var.environment}-${var.region_code}-${var.workload}"

  # Default traffic split: 100% to the latest revision when none supplied.
  ingress_traffic_weights = (
    var.ingress == null ? [] :
    length(var.ingress.traffic_weights) > 0 ? var.ingress.traffic_weights :
    [{ percentage = 100, latest_revision = true, revision_suffix = null, label = null }]
  )
}

###############################################################
# RESOURCE: Container App
###############################################################
resource "azurerm_container_app" "this" {
  name                         = local.name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  revision_mode                = var.revision_mode
  workload_profile_name        = var.workload_profile_name
  max_inactive_revisions       = var.max_inactive_revisions

  template {
    min_replicas                     = var.min_replicas
    max_replicas                     = var.max_replicas
    revision_suffix                  = var.revision_suffix
    cooldown_period_in_seconds       = var.cooldown_period_in_seconds
    polling_interval_in_seconds      = var.polling_interval_in_seconds
    termination_grace_period_seconds = var.termination_grace_period_seconds

    dynamic "init_container" {
      for_each = var.init_containers
      content {
        name    = init_container.value.name
        image   = init_container.value.image
        cpu     = init_container.value.cpu
        memory  = init_container.value.memory
        args    = init_container.value.args
        command = init_container.value.command

        dynamic "env" {
          for_each = init_container.value.env
          content {
            name        = env.value.name
            value       = env.value.value
            secret_name = env.value.secret_name
          }
        }

        dynamic "volume_mounts" {
          for_each = init_container.value.volume_mounts
          content {
            name     = volume_mounts.value.name
            path     = volume_mounts.value.path
            sub_path = volume_mounts.value.sub_path
          }
        }
      }
    }

    dynamic "container" {
      for_each = var.containers
      content {
        name    = container.value.name
        image   = container.value.image
        cpu     = container.value.cpu
        memory  = container.value.memory
        args    = container.value.args
        command = container.value.command

        dynamic "env" {
          for_each = container.value.env
          content {
            name        = env.value.name
            value       = env.value.value
            secret_name = env.value.secret_name
          }
        }

        dynamic "liveness_probe" {
          for_each = container.value.liveness_probe != null ? [container.value.liveness_probe] : []
          content {
            port                    = liveness_probe.value.port
            transport               = liveness_probe.value.transport
            path                    = liveness_probe.value.path
            host                    = liveness_probe.value.host
            initial_delay           = liveness_probe.value.initial_delay
            interval_seconds        = liveness_probe.value.interval_seconds
            timeout                 = liveness_probe.value.timeout
            failure_count_threshold = liveness_probe.value.failure_count_threshold

            dynamic "header" {
              for_each = liveness_probe.value.headers
              content {
                name  = header.value.name
                value = header.value.value
              }
            }
          }
        }

        dynamic "readiness_probe" {
          for_each = container.value.readiness_probe != null ? [container.value.readiness_probe] : []
          content {
            port                    = readiness_probe.value.port
            transport               = readiness_probe.value.transport
            path                    = readiness_probe.value.path
            host                    = readiness_probe.value.host
            initial_delay           = readiness_probe.value.initial_delay
            interval_seconds        = readiness_probe.value.interval_seconds
            timeout                 = readiness_probe.value.timeout
            failure_count_threshold = readiness_probe.value.failure_count_threshold
            success_count_threshold = readiness_probe.value.success_count_threshold

            dynamic "header" {
              for_each = readiness_probe.value.headers
              content {
                name  = header.value.name
                value = header.value.value
              }
            }
          }
        }

        dynamic "startup_probe" {
          for_each = container.value.startup_probe != null ? [container.value.startup_probe] : []
          content {
            port                    = startup_probe.value.port
            transport               = startup_probe.value.transport
            path                    = startup_probe.value.path
            host                    = startup_probe.value.host
            initial_delay           = startup_probe.value.initial_delay
            interval_seconds        = startup_probe.value.interval_seconds
            timeout                 = startup_probe.value.timeout
            failure_count_threshold = startup_probe.value.failure_count_threshold

            dynamic "header" {
              for_each = startup_probe.value.headers
              content {
                name  = header.value.name
                value = header.value.value
              }
            }
          }
        }

        dynamic "volume_mounts" {
          for_each = container.value.volume_mounts
          content {
            name     = volume_mounts.value.name
            path     = volume_mounts.value.path
            sub_path = volume_mounts.value.sub_path
          }
        }
      }
    }

    dynamic "http_scale_rule" {
      for_each = var.http_scale_rules
      content {
        name                = http_scale_rule.value.name
        concurrent_requests = http_scale_rule.value.concurrent_requests
        dynamic "authentication" {
          for_each = http_scale_rule.value.authentications
          content {
            secret_name       = authentication.value.secret_name
            trigger_parameter = authentication.value.trigger_parameter
          }
        }
      }
    }

    dynamic "tcp_scale_rule" {
      for_each = var.tcp_scale_rules
      content {
        name                = tcp_scale_rule.value.name
        concurrent_requests = tcp_scale_rule.value.concurrent_requests
        dynamic "authentication" {
          for_each = tcp_scale_rule.value.authentications
          content {
            secret_name       = authentication.value.secret_name
            trigger_parameter = authentication.value.trigger_parameter
          }
        }
      }
    }

    dynamic "custom_scale_rule" {
      for_each = var.custom_scale_rules
      content {
        name             = custom_scale_rule.value.name
        custom_rule_type = custom_scale_rule.value.custom_rule_type
        metadata         = custom_scale_rule.value.metadata
        dynamic "authentication" {
          for_each = custom_scale_rule.value.authentications
          content {
            secret_name       = authentication.value.secret_name
            trigger_parameter = authentication.value.trigger_parameter
          }
        }
      }
    }

    dynamic "azure_queue_scale_rule" {
      for_each = var.azure_queue_scale_rules
      content {
        name         = azure_queue_scale_rule.value.name
        queue_name   = azure_queue_scale_rule.value.queue_name
        queue_length = azure_queue_scale_rule.value.queue_length
        dynamic "authentication" {
          for_each = azure_queue_scale_rule.value.authentications
          content {
            secret_name       = authentication.value.secret_name
            trigger_parameter = authentication.value.trigger_parameter
          }
        }
      }
    }

    dynamic "volume" {
      for_each = var.volumes
      content {
        name          = volume.value.name
        storage_type  = volume.value.storage_type
        storage_name  = volume.value.storage_name
        mount_options = volume.value.mount_options
      }
    }
  }

  dynamic "ingress" {
    for_each = var.ingress != null ? [var.ingress] : []
    content {
      target_port                = ingress.value.target_port
      external_enabled           = ingress.value.external_enabled
      transport                  = ingress.value.transport
      allow_insecure_connections = ingress.value.allow_insecure_connections
      exposed_port               = ingress.value.exposed_port
      client_certificate_mode    = ingress.value.client_certificate_mode

      dynamic "traffic_weight" {
        for_each = local.ingress_traffic_weights
        content {
          percentage      = traffic_weight.value.percentage
          latest_revision = traffic_weight.value.latest_revision
          revision_suffix = traffic_weight.value.revision_suffix
          label           = traffic_weight.value.label
        }
      }

      dynamic "cors" {
        for_each = ingress.value.cors != null ? [ingress.value.cors] : []
        content {
          allowed_origins           = cors.value.allowed_origins
          allow_credentials_enabled = cors.value.allow_credentials_enabled
          allowed_headers           = cors.value.allowed_headers
          allowed_methods           = cors.value.allowed_methods
          exposed_headers           = cors.value.exposed_headers
          max_age_in_seconds        = cors.value.max_age_in_seconds
        }
      }

      dynamic "ip_security_restriction" {
        for_each = ingress.value.ip_security_restrictions
        content {
          name             = ip_security_restriction.value.name
          action           = ip_security_restriction.value.action
          ip_address_range = ip_security_restriction.value.ip_address_range
          description      = ip_security_restriction.value.description
        }
      }
    }
  }

  dynamic "identity" {
    for_each = var.identity != null ? [var.identity] : []
    content {
      type         = identity.value.type
      identity_ids = length(identity.value.identity_ids) > 0 ? identity.value.identity_ids : null
    }
  }

  dynamic "registry" {
    for_each = var.registries
    content {
      server               = registry.value.server
      identity             = registry.value.identity
      username             = registry.value.username
      password_secret_name = registry.value.password_secret_name
    }
  }

  dynamic "secret" {
    for_each = var.secrets
    content {
      name                = secret.value.name
      value               = secret.value.value
      key_vault_secret_id = secret.value.key_vault_secret_id
      identity            = secret.value.identity
    }
  }

  dynamic "dapr" {
    for_each = var.dapr != null ? [var.dapr] : []
    content {
      app_id       = dapr.value.app_id
      app_port     = dapr.value.app_port
      app_protocol = dapr.value.app_protocol
    }
  }

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  lifecycle {
    precondition {
      condition     = length(local.name) >= 2 && length(local.name) <= 32
      error_message = "The composed Container App name \"${local.name}\" must be 2-32 characters. Shorten `workload` or pass an explicit `name`."
    }
  }
}

###############################################################
# RESOURCE: Management Lock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_container_app.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}
