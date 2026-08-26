<#
.SYNOPSIS
    Register this AVM-style monorepo as a single module entry in HCP
    Terraform's private registry.

.DESCRIPTION
    Since the repo follows the AVM `terraform-<provider>-<name>` layout
    (root module at the top level, submodules under `modules/`, examples
    under `examples/`), HCP Terraform publishes it as ONE module —
    "John6810/landing-zone/azurerm" — and auto-discovers every submodule
    and example. There is no per-module registration to do.

    The "Submodules" and "Examples" dropdowns in the registry UI are
    populated automatically from the `modules/` and `examples/` folders
    on each tagged release.

    This script POSTs to
        https://<hostname>/api/v2/organizations/<org>/registry-modules/vcs
    with `vcs-repo.tags = true` and no tag-prefix / source-directory —
    HCP TF infers `name` ("landing-zone") and `module_provider`
    ("azurerm") from the repo name.

    The script is idempotent: HCP TF returns 422 if the module is
    already registered, which is reported as [SKIP] and does not fail.

.PARAMETER Organization
    HCP Terraform organization name (e.g. "John6810").

.PARAMETER OAuthTokenId
    OAuth Token ID of the VCS provider connection in HCP TF.
    Format: "ot-XXXXXXXXXXXXXXXX".
    Find it in HCP TF -> Settings -> Version Control -> click your provider.

.PARAMETER VcsIdentifier
    GitHub repository identifier, "<owner>/<repo>" format.
    Defaults to "John6810/terraform-azurerm-landing-zone".

.PARAMETER Token
    HCP Terraform USER token (NOT an organization token — those cannot
    create registry modules). Read from $env:TFE_TOKEN if omitted.
    Create one at HCP TF -> User Settings -> Tokens.

.PARAMETER Hostname
    HCP Terraform / TFE hostname. Defaults to "app.terraform.io".

.PARAMETER DryRun
    Print the payload that would be sent without making any API call.

.EXAMPLE
    $env:TFE_TOKEN = "..."
    .\scripts\Register-HcpRegistryModules.ps1 `
        -Organization John6810 `
        -OAuthTokenId ot-XXXXXXXXXXXXXXXX

.EXAMPLE
    # Preview the payload
    .\scripts\Register-HcpRegistryModules.ps1 `
        -Organization John6810 `
        -OAuthTokenId ot-XXXXXXXXXXXXXXXX `
        -DryRun
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Organization,

    [Parameter(Mandatory)]
    [string]$OAuthTokenId,

    [string]$VcsIdentifier = "John6810/terraform-azurerm-landing-zone",

    [string]$Token = $env:TFE_TOKEN,

    [string]$Hostname = "app.terraform.io",

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if (-not $Token -and -not $DryRun) {
    throw "No HCP TF token. Set `$env:TFE_TOKEN or pass -Token. (User token, not org token.)"
}

Write-Host "Org: $Organization | VCS: $VcsIdentifier | Hostname: $Hostname" -ForegroundColor Cyan
if ($DryRun) { Write-Host "DRY RUN -- no API call will be made." -ForegroundColor Yellow }

$Payload = @{
    data = @{
        type       = "registry-modules"
        attributes = @{
            "vcs-repo" = @{
                identifier           = $VcsIdentifier
                "display-identifier" = $VcsIdentifier
                "oauth-token-id"     = $OAuthTokenId
                tags                 = $true
            }
        }
    }
}

$Body = $Payload | ConvertTo-Json -Depth 10

if ($DryRun) {
    Write-Host "Payload:" -ForegroundColor Yellow
    Write-Host $Body
    return
}

$Headers = @{
    "Authorization" = "Bearer $Token"
    "Content-Type"  = "application/vnd.api+json"
}

$Uri = "https://$Hostname/api/v2/organizations/$Organization/registry-modules/vcs"

try {
    $resp = Invoke-RestMethod -Method Post -Uri $Uri -Headers $Headers -Body $Body
    Write-Host "[OK] Registered $($resp.data.attributes.name) ($($resp.data.attributes.provider)) -> $($resp.data.id)" -ForegroundColor Green
    Write-Host "Registry page: https://$Hostname/app/$Organization/registry/modules/private/$Organization/$($resp.data.attributes.name)/$($resp.data.attributes.provider)" -ForegroundColor Cyan
} catch {
    $Status = $null
    if ($_.Exception.Response) { $Status = [int]$_.Exception.Response.StatusCode }

    if ($Status -in 409, 422) {
        $msg = $_.ErrorDetails.Message
        if ($msg -match 'has already been taken' -or $msg -match 'already exists') {
            Write-Host "[SKIP] Module already registered for this repo." -ForegroundColor Yellow
            return
        }
    }

    $detail = $_.ErrorDetails.Message
    if (-not $detail) { $detail = $_.Exception.Message }
    Write-Host "[FAIL] ($Status): $detail" -ForegroundColor Red
    exit 1
}
