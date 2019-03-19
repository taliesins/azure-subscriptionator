$ErrorActionPreference = "Stop"

$currentWorkingDirectory = $PWD.Path
$configPath = Join-Path -Path $currentWorkingDirectory -ChildPath 'Config.json'
$configJson = [System.IO.File]::ReadAllText($configPath)
$config = ConvertFrom-Json $configJson

$tenantId = $config.Tenant.Id

#ensure that you are logged in
Connect-AzAccount -TenantId $tenantId