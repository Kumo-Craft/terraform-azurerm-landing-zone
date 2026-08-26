# Dummy variable values used by TFLint for STATIC EVALUATION ONLY (see
# .github/workflows/iac-security.yml). Never used at deploy time.
#
# Modules build their names via coalesce()/interpolation over these nullable
# convention variables. With every var null (TFLint's default when nothing is
# supplied), an expression like `coalesce(var.environment, "")` errors with
# "no non-null, non-empty-string arguments" and TFLint aborts the WHOLE module.
# Supplying valid convention values lets TFLint evaluate the naming logic and
# lint the module for real. Values respect each module's validation patterns
# (subscription_acronym ^[a-z]{2,5}$, environment ^[a-z]{2,4}$, region_code
# ^[a-z]{2,5}$, workload ^[a-z][a-z0-9-]{0,20}$). Modules that don't declare a
# given variable simply ignore it.
#
# NB: this filename is NOT auto-loaded by Terraform (only *.auto.tfvars /
# terraform.tfvars are), so it never affects a real plan/apply.

subscription_acronym = "acr"
environment          = "dev"
region_code          = "gwc"
workload             = "wl"
