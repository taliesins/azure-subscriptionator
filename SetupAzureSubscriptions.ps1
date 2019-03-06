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
$TenantId = "1931b7d3-bd07-4b36-9814-adf4ad406860"

#ensure that you are logged in
#Connect-AzAccount -TenantId $TenantId

$FullyManage = $true

$tenantContext = Connect-DscContext -TenantId $TenantId

if (!$tenantContext.ManagementGroupName) {
    throw "The tenant $TenantId does not exist or is not accessible to this user"
}

if (!$tenantContext.EnrollmentAccountId) {
    Write-Host "No enrollment account, will not be able to create subscriptions"
}

$DesiredState = [System.IO.File]::ReadAllLines((Resolve-Path 'DesiredState.json')) | ConvertFrom-Json 

#Create definitions at root, then all management groups can apply them at any level
$ManagementGroups = Set-DscManagementGroup -DesiredState $DesiredState -DeleteUnknownManagementGroups $FullyManage
$Subscriptions = Set-DscSubscription -DesiredState $DesiredState -CancelUnknownSubscriptions $FullyManage
$AdGroups = Set-DscAdGroup -DesiredState $DesiredState -DeleteUnknownAdGroups $FullyManage -DeleteUnknownAdGroupMembers $FullyManage

$RoleDefinitions = Set-DscRoleDefinition -RoleDefinitionPath (Resolve-Path 'RoleDefinitions') -TenantId $TenantId
$PolicyDefinitions = Set-DscPolicyDefinition -ManagementGroupName $tenantContext.ManagementGroupName -PolicyDefinitionPath (Resolve-Path 'PolicyDefinitions')
$PolicySetDefinitions = Set-DscPolicySetDefinition -ManagementGroupName $tenantContext.ManagementGroupName -PolicySetDefinitionPath (Resolve-Path 'PolicySetDefinitions')
$BlueprintDefinitions = Set-DscBlueprintDefinition -ManagementGroupName $tenantContext.ManagementGroupName -TenantId $TenantId -BlueprintDefinitionPath (Resolve-Path 'Blueprints')

#Add role to management group or subscription
$RoleAssignments = Set-DscRoleAssignment -DesiredState $DesiredState

#Add policy to management group or subscription
$PolicyAssignments = Set-DscPolicyAssignment -DesiredState $DesiredState

#Add policy set to management group or subscription
$PolicySetAssignments = Set-DscPolicySetAssignment -DesiredState $DesiredState

#Add blueprint to subscriptions
$BlueprintAssignments = Set-DscBlueprintAssignment -DesiredState $DesiredState

#https://docs.microsoft.com/en-us/rest/api/policy-insights/
#Do this to show the number of non complaint resources
#https://docs.microsoft.com/en-us/azure/governance/policy/assign-policy-powershell
