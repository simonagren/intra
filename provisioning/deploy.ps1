Param(
    [Parameter(Mandatory = $true, Position = 1)]
    [string]$TenantUrl,

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$SitePrefix = "SOGETI_",

    [Parameter(Mandatory = $false, Position = 2)]
    [PSCredential]$Credentials,

    [Parameter(Mandatory = $false, Position = 3)]
    [switch]$Build,

    [Parameter(Mandatory = $false, Position = 3)]
    [switch]$SkipPowerShellInstall = $false,

    [Parameter(Mandatory = $false, Position = 3)]
    [switch]$SkipSiteCreation = $false,

    [Parameter(Mandatory = $false)]
    [switch]$SkipSolutionDeployment = $false,

    [Parameter(Mandatory = $false)]
    [string]$Company = "Sogeti",

    [Parameter(Mandatory = $false)]
    [string]$WeatherCity = "Umeå",

    [Parameter(Mandatory = $false)]
    [string]$StockSymbol = "SOGETI",

    [Parameter(Mandatory = $false)]
    [string]$StockAPIKey = ""
)    


# Load helper functions
. "$PSScriptRoot\functions.ps1"

# Check if PnP PowerShell is installed
if (!$SkipPowershellInstall) {
    $modules = Get-Module -Name SharePointPnPPowerShellOnline -ListAvailable
    if ($modules -eq $null) {
        # Not installed.
        Install-Module -Name SharePointPnPPowerShellOnline -Scope CurrentUser -Force
        Import-Module -Name SharePointPnPPowerShellOnline -DisableNameChecking
    }
}

if ($Credentials -eq $null) {
    $Credentials = Get-Credential -Message "Enter credentials to connect to $TenantUrl"
}

if ($SkipSiteCreation -eq $false) {
    # check if URL is valid
    $SiteUrl = New-SiteHierarchy -TenantUrl $TenantUrl -Prefix $SitePrefix -ConfigurationFilePath ./hierarchy.json -Credentials $Credentials
    if ($SiteUrl -isnot [array]) {
        $SiteUrl = @($SiteUrl)
    }
}
else {
    $hierarchy = ConvertFrom-Json (Get-Content -Path ./hierarchy.json -Raw)
    $SiteUrl = @("$TenantUrl/sites/$SitePrefix$($hierarchy.url)")
}

# Check if package existsd
if ((Test-Path "$PSScriptRoot\..\solution\sharepoint\solution\sogeti-starter-kit.sppkg") -eq $false -or $Build) {
    Set-Location $PSScriptRoot\..\solution
    npm install
    # does not exist. Build and Package
    gulp -f "gulpfile.js" clean 2>&1 | Out-Null
    Write-Host "Building solution" -ForegroundColor Cyan
    gulp -f "gulpfile.js" build 2>&1 | Out-Null
    Write-Host "Bundling solution" -ForegroundColor Cyan
    gulp -f "gulpfile.js" bundle --ship 2>&1 | Out-Null
    Write-Host "Packaging solution" -ForegroundColor Cyan 
    gulp -f "gulpfile.js" package-solution --ship 2>&1 | Out-Null

    #return to provisioning folder
    Set-Location $PSScriptRoot\..\provisioning
}
$connection = Connect-PnPOnline -Url ($SiteUrl | Select-Object -First 1) -Credentials $Credentials -ReturnConnection

if ($SkipSolutionDeployment -ne $true) {
    # Temporary until schema change is present
    Write-Host "Provisioning solution" -ForegroundColor Cyan
    $existingApp = Get-PnPApp -Identity "sogeti-starter-kit" -ErrorAction SilentlyContinue
    if ($existingApp -ne $null) {
        Remove-PnPApp -Identity $existingApp
    }
    Apply-PnPProvisioningTemplate -Path "$PSScriptRoot\solution.xml" -Connection $connection
    Write-Host "Provisioning Taxonomy" -ForegroundColor Cyan
    Apply-PnPProvisioningTemplate -Path "$PSScriptRoot\terms.xml" -Connection $connection
    Update-AppIfPresent -AppName "sogeti-starter-kit-client-side-solution" -Connection $connection
}

# Disable Quicklaunch for Hubsite
$web = Get-PnPWeb -Connection $connection
$web.QuicklaunchEnabled = $false
$web.Update()
Invoke-PnPQuery -Connection $connection

# Create and Set theme if needed
Set-ThemeIfNotSet -Connection $connection

# Register the site as the hubsite
$isHub = Get-PnPHubSite -Identity ($SiteUrl | Select-Object -First 1) -ErrorAction SilentlyContinue -Connection $connection
if ($isHub -eq $null) {
    Write-Host "Registering site as hubsite" -ForegroundColor Cyan
    Register-PnPHubSite -Site $SiteUrl -Connection $connection 2>&1 | Out-Null
    
}
$HubSiteInfo = Get-PnPSite -Includes Id, RootWeb.Language
$HubSiteId = $HubSiteInfo.Id.ToString()
$HubSiteLcid = $HubSiteInfo.RootWeb.Language.ToString()

if ($StockAPIKey -ne $null -and $StockAPIKey -ne "") {
    Write-Host "Storing Stock API Key in tenant properties"
    Set-PnPStorageEntity -Key "PnP-Portal-AlphaVantage-API-Key" -Value $StockAPIKey -Comment "API Key for Alpha Advantage REST Stock service" -Description "API Key for Alpha Advantage REST Stock service" -Connection $connection
}

Write-Host "Applying template to hubsite" -ForegroundColor Cyan
Apply-PnPProvisioningTemplate -Path "$PSScriptRoot\hubsite.xml" -Parameters @{"WeatherCity" = $WeatherCity; "PortalTitle" = "$Company Portal"; "StockSymbol" = $StockSymbol; "HubSiteId" = $HubSiteId; "Company" = $Company; "lcid" = $HubSiteLcid} -Connection $connection
Apply-PnPProvisioningTemplate -Path "$PSScriptRoot\SnS-PortalFooter-Links.xml" -Connection $connection

# Due to bug in the provisioning engine reassociate the designs to the correct templates
$teamsitedesign = Get-PnPSiteDesign | Where-Object{$_.Title -eq "$Company Team Site"}
Set-PnPSiteDesign -Identity $teamsitedesign -WebTemplate TeamSite
$communicationsitedesign = Get-PnPSiteDesign | Where-Object{$_.Title -eq "$Company Communication Site"}
Set-PnPSiteDesign -Identity $communicationsitedesign -WebTemplate CommunicationSite

Write-Host "Updating navigation and applying collab templates"
$departmentNode = Get-PnPNavigationNode -Location TopNavigationBar -Connection $connection | Where-Object {$_.Title -eq "Departments"} 
$children = Get-PnPProperty -ClientObject $departmentNode -Property Children
$hierarchy = ConvertFrom-Json (Get-Content -Path "$PSScriptRoot\hierarchy.json" -Raw)
foreach ($child in $hierarchy.children) {
    if (($children | Where-Object {$_.Title -eq $child.title}) -eq $null) {
        $node = Add-PnPNavigationNode -Location TopNavigationBar -Parent $departmentNode[0].Id -Title $child.title -Url "$TenantUrl/sites/$SitePrefix$($child.url)" -Connection $connection
        $childConnection = Connect-PnPOnline -Url "$TenantUrl/sites/$SitePrefix$($child.url)" -Credentials $Credentials -ReturnConnection
    }
    Apply-PnPProvisioningTemplate -Path "$PSScriptRoot\collab.xml" -Connection $childConnection
}

Write-Host "Done." -ForegroundColor Green

