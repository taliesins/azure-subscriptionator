Import-Module .\Subscriptionator.psm1 -Force

#ensure there is an AD Tenant
#https://portal.azure.com/#create/Microsoft.AzureActiveDirectory

#ensure you are logged in with user that has rights to manage subscriptions and management groups
#https://portal.azure.com/#blade/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/Properties
#Under Access management for Azure resources
#select  "yes" for can manage access to all azure subscriptions and management groups in this directory

#ensure you are logged in with a user that has rights to create subscriptions:
#https://docs.microsoft.com/bs-latn-ba/azure/azure-resource-manager/grant-access-to-create-subscription?tabs=azure-powershell
# $EnrollmentAccountId = Get-AzEnrollmentAccount | %{$_.ObjectId}
# $UserObjectId = Get-AzADUser -UserPrincipalName "taliesins@TaliTest01.onmicrosoft.com" | %{$_.Id}
# New-AzureRmRoleAssignment -RoleDefinitionName Owner -ObjectId $UserObjectId -Scope "/providers/Microsoft.Billing/enrollmentAccounts/$EnrollmentAccountId"

#ensure the Az Context has been set for the tenant
$currentWorkingDirectory = $PWD.Path
$configPath = Join-Path -Path $currentWorkingDirectory -ChildPath 'Config.json'
$config = [System.IO.File]::ReadAllText(($configPath)) | ConvertFrom-Json
$definitionManagementGroupName=$config.Tenant.DefinitionManagementGroup
if (!$definitionManagementGroupName){
    $definitionManagementGroupName = $config.Tenant.Id
}

$tenantId = $config.Tenant.Id

#ensure that you are logged in
#Connect-AzAccount -TenantId $tenantId

$tenantContext = Get-DscContext -TenantId $tenantId

if (!$definitionManagementGroupName) {
    throw "The tenant $tenantId does not exist or is not accessible to this user"
}

if (!$tenantContext.EnrollmentAccountId) {
    Write-Host "No enrollment account, will not be able to create subscriptions"
}


$desiredStatePath = Join-Path -Path $currentWorkingDirectory -ChildPath 'DesiredState.json'
$desiredState = [System.IO.File]::ReadAllText(($desiredStatePath)) | ConvertFrom-Json 

#Create definitions at root, then all management groups can apply them at any level
Write-Host 'Deploying AD groups'
$deleteUnknownAdGroups=$config.Tenant.DeleteUnknownAdGroups 
$deleteUnknownAdGroupMembers=$config.Tenant.DeleteUnknownAdGroupMembers
#$adGroups = Set-DscAdGroup -DesiredState $desiredState -DeleteUnknownAdGroups $deleteUnknownAdGroups -DeleteUnknownAdGroupMembers $deleteUnknownAdGroupMembers

Write-Host 'Deploying management groups'
$deleteUnknownManagementGroups = $config.Tenant.DeleteUnknownManagementGroups
#$managementGroups = Set-DscManagementGroup -DesiredState $desiredState -DeleteUnknownManagementGroups $deleteUnknownManagementGroups

Write-Host 'Deploying subscriptions'
$cancelUnknownSubscriptions=$config.Tenant.CancelUnknownSubscriptions
#$subscriptions = Set-DscSubscription -DesiredState $desiredState -CancelUnknownSubscriptions $cancelUnknownSubscriptions

Write-Host 'Deploying role definitions'
$roleDefinitionsPath = Join-Path -Path $currentWorkingDirectory -ChildPath 'RoleDefinitions'
$deleteUnknownRoleDefinitions = $config.Tenant.DeleteUnknownRoleDefinitions
#$roleDefinitions = Set-DscRoleDefinition -RoleDefinitionPath $roleDefinitionsPath -TenantId $tenantId -DeleteUnknownRoleDefinitions $deleteUnknownRoleDefinitions

Write-Host 'Deploying policy definitions'
$policyDefinitionsPath = Join-Path -Path $currentWorkingDirectory -ChildPath 'PolicyDefinitions'
$deleteUnknownPolicyDefinitions = $config.Tenant.DeleteUnknownPolicyDefinitions
#$policyDefinitions = Set-DscPolicyDefinition -ManagementGroupName $definitionManagementGroupName -PolicyDefinitionPath $policyDefinitionsPath -DeleteUnknownPolicyDefinitions $deleteUnknownPolicyDefinitions

Write-Host 'Deploying policy set definitions'
$policySetDefinitionsPath = Join-Path -Path $currentWorkingDirectory -ChildPath 'PolicySetDefinitions'
$deleteUnknownPolicySetDefinitions = $config.Tenant.DeleteUnknownPolicySetDefinitions
$policySetDefinitions = Set-DscPolicySetDefinition -ManagementGroupName $definitionManagementGroupName -PolicySetDefinitionPath $policySetDefinitionsPath -DeleteUnknownPolicySetDefinitions $deleteUnknownPolicySetDefinitions

Write-Host 'Deploying blueprint definitions'
$blueprintDefinitionsPath = Join-Path -Path $currentWorkingDirectory -ChildPath 'Blueprints'
$deleteUnknownBlueprints = $config.Tenant.DeleteUnknownBlueprints
$autoPublishBlueprints = $config.Tenant.AutoPublishBlueprints
$blueprintDefinitions = Set-DscBlueprintDefinition -ManagementGroupName $definitionManagementGroupName -TenantId $tenantId -BlueprintDefinitionPath $blueprintDefinitionsPath -DeleteUnknownBlueprints $deleteUnknownBlueprints -AutoPublishBlueprints $autoPublishBlueprints

#Add role to management group or subscription
Write-Host 'Deploying role assignments'
$deleteUnknownRoleAssignments = $config.Tenant.DeleteUnknownRoleAssignments
$roleAssignments = Set-DscRoleAssignment -DesiredState $desiredState -DeleteUnknownRoleAssignments $deleteUnknownRoleAssignments

#Add policy to management group or subscription
Write-Host 'Deploying policy assignments'
$deleteUnknownPolicyAssignments = $config.Tenant.DeleteUnknownPolicyAssignments
$policyAssignments = Set-DscPolicyAssignment -DesiredState $desiredState -DeleteUnknownPolicyAssignments $deleteUnknownPolicyAssignments

#Add policy set to management group or subscription
Write-Host 'Deploying policy set assignments'
$deleteUnknownPolicySetAssignments = $config.Tenant.DeleteUnknownPolicySetAssignments
$policySetAssignments = Set-DscPolicySetAssignment -DesiredState $desiredState -DeleteUnknownPolicySetAssignments $deleteUnknownPolicySetAssignments

#Add blueprint to subscriptions
Write-Host 'Deploying blueprint assignments'
$deleteUnknownBlueprintAssignments = $config.Tenant.DeleteUnknownBlueprintAssignments
$blueprintAssignments = Set-DscBlueprintAssignment -DesiredState $desiredState -DeleteUnknownBlueprintAssignments $deleteUnknownBlueprintAssignments

#https://docs.microsoft.com/en-us/rest/api/policy-insights/
#Do this to show the number of non complaint resources
#https://docs.microsoft.com/en-us/azure/governance/policy/assign-policy-powershell
