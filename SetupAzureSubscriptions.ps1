#UnInstall-Module -Name AzureRM
#Install-Module -Name AzureRM

#UnInstall-Module -Name AzureAD
#Install-Module -Name AzureAD

$tenantAdminAccount = 'tali@talifuntest.onmicrosoft.com'
$tenantId = 'e8815a32-7f83-417f-852b-36ac13dec95d'
$tenantAdminCredential = Get-Credential -UserName $tenantAdminAccount -Message "Credentials for global adminstrator for tenant"

Connect-AzureRmAccount -Credential $tenantAdminCredential -Environment $rootEnvironment
Connect-AzureAD -Credential $tenantAdminCredential -AzureEnvironmentName $rootEnvironment
#Get-AzureRmEnrollmentAccount

$parentIdPrefix = '/providers/Microsoft.Management/managementGroups/'
$subscriptionOfferTypeProduction = 'MS-AZR-0017P'
$subscriptionOfferTypeDevTest = 'MS-AZR-0148P' #https://azure.microsoft.com/en-us/offers/ms-azr-0148p/

#ensure there is an AD Tenant
#https://portal.azure.com/#create/Microsoft.AzureActiveDirectory

#ensure you are logged in with user that has rights to manage subscriptions and management groups
#https://portal.azure.com/#blade/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/Properties
#Under Access management for Azure resources
#select  "yes" for can manage access to all azure subscriptions and management groups in this directory

$scriptPath = Split-Path -parent $PSCommandPath
$AzureRMPath = Join-Path $scriptPath "azurerm.6.13.1\AzureRM.psd1"
if (!(Get-Module AzureRM)){
    Import-Module -Name $AzureRMPath
}

$AzureRMManagementGroupsPath = Join-Path $scriptPath "azurerm.managementgroups.0.0.1-preview\AzureRM.ManagementGroups.psd1"
if (!(Get-Module AzureRM.MangagementGroups)){
    Import-Module -Name $AzureRMManagementGroupsPath
}

$AzureRMBlueprintPath = Join-Path $scriptPath "manage-azurermblueprint.2.0.0\Manage-AzureRMBlueprint.ps1"
#if (!(Get-Module AzureRM.Blueprint)){
#    Import-Module -Name $AzureRMBlueprintPath
#}

$AzureRMSubscriptionPath = Join-Path $scriptPath "azurerm.subscription.0.2.3-preview\AzureRM.Subscription.psd1"
if (!(Get-Module AzureRM.Subscription)){
    Import-Module -Name $AzureRMSubscriptionPath
}

$AzureADPath = Join-Path $scriptPath "azuread.2.0.2.4\AzureAD.psd1"
if (!(Get-Module AzureAD)){
    Import-Module -Name $AzureADPath
}

function Get-ClonedObject {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [hashtable] $DeepCopyObject
    )

    $memStream = new-object IO.MemoryStream
    $formatter = new-object Runtime.Serialization.Formatters.Binary.BinaryFormatter
    $formatter.Serialize($memStream,$DeepCopyObject)
    $memStream.Position=0
    $formatter.Deserialize($memStream)
}

function Get-TopologicalSort {
  param(
      [Parameter(Mandatory = $true, Position = 0)]
      [hashtable] $edgeList
  )

  # Make sure we can use HashSet
  Add-Type -AssemblyName System.Core

  # Clone it so as to not alter original
  $currentEdgeList = [hashtable] (Get-ClonedObject $edgeList)

  # algorithm from http://en.wikipedia.org/wiki/Topological_sorting#Algorithms
  $topologicallySortedElements = New-Object System.Collections.ArrayList
  $setOfAllNodesWithNoIncomingEdges = New-Object System.Collections.Queue

  $fasterEdgeList = @{}

  # Keep track of all nodes in case they put it in as an edge destination but not source
  $allNodes = New-Object -TypeName System.Collections.Generic.HashSet[object] -ArgumentList (,[object[]] $currentEdgeList.Keys)

  foreach($currentNode in $currentEdgeList.Keys) {
      $currentDestinationNodes = [array] $currentEdgeList[$currentNode]
      if($currentDestinationNodes.Length -eq 0) {
          $setOfAllNodesWithNoIncomingEdges.Enqueue($currentNode)
      }

      foreach($currentDestinationNode in $currentDestinationNodes) {
          if(!$allNodes.Contains($currentDestinationNode)) {
              [void] $allNodes.Add($currentDestinationNode)
          }
      }

      # Take this time to convert them to a HashSet for faster operation
      $currentDestinationNodes = New-Object -TypeName System.Collections.Generic.HashSet[object] -ArgumentList (,[object[]] $currentDestinationNodes )
      [void] $fasterEdgeList.Add($currentNode, $currentDestinationNodes)        
  }

  # Now let's reconcile by adding empty dependencies for source nodes they didn't tell us about
  foreach($currentNode in $allNodes) {
      if(!$currentEdgeList.ContainsKey($currentNode)) {
          [void] $currentEdgeList.Add($currentNode, (New-Object -TypeName System.Collections.Generic.HashSet[object]))
          $setOfAllNodesWithNoIncomingEdges.Enqueue($currentNode)
      }
  }

  $currentEdgeList = $fasterEdgeList

  while($setOfAllNodesWithNoIncomingEdges.Count -gt 0) {        
      $currentNode = $setOfAllNodesWithNoIncomingEdges.Dequeue()
      [void] $currentEdgeList.Remove($currentNode)
      [void] $topologicallySortedElements.Add($currentNode)

      foreach($currentEdgeSourceNode in $currentEdgeList.Keys) {
          $currentNodeDestinations = $currentEdgeList[$currentEdgeSourceNode]
          if($currentNodeDestinations.Contains($currentNode)) {
              [void] $currentNodeDestinations.Remove($currentNode)

              if($currentNodeDestinations.Count -eq 0) {
                  [void] $setOfAllNodesWithNoIncomingEdges.Enqueue($currentEdgeSourceNode)
              }                
          }
      }
  }

  if($currentEdgeList.Count -gt 0) {
      throw 'Graph has at least one cycle!'
  }

  return $topologicallySortedElements
}

function Get-TopologicalSortedAzureRmAdGroups {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $AzureRmAdGroups
    )

    $azureRmAdGroupNames = @{} 
    $AzureRmAdGroups | %{
        $value = $_.DisplayName
        $_.Members | %{
            $key = $_.DisplayName
            $azureRmAdGroupNames[$key]+=@($value)
        }
        $azureRmAdGroupNames[$value]+=@()
    }
    $topologicalSortedAzureRmAdGroupNames = Get-TopologicalSort -edgeList $azureRmAdGroupNames | ?{$_ -and $AzureRmAdGroups.DisplayName.Contains($_)}
    [array]::Reverse($topologicalSortedAzureRmAdGroupNames)
    $topologicalSortedAzureRmAdGroups = @()

    $topologicalSortedAzureRmAdGroupNames | %{
        $adGroupName = $_
        $topologicalSortedAzureRmAdGroups += $AzureRmAdGroups |? {$_.DisplayName -eq $adGroupName}
    }

    $topologicalSortedAzureRmAdGroups
}

Function Set-DscAdGroup {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $AdGroups,
        [Parameter(Mandatory = $false, Position = 1)]
        $DeleteUnknownAdGroupMembers = $false,
        [Parameter(Mandatory = $false, Position = 2)]
        $DeleteUnknownAdGroups = $false
    )

    $currentAdGroups = @(Get-AzureADGroup | ?{ $_.ObjectType -eq 'Group'} | %{
        $objectId = $_.ObjectId
        $displayName = $_.DisplayName
        $description = $_.Description
        $members = @(Get-AzureADGroupMember -ObjectId $objectId | ?{ $_.ObjectType -eq 'Group'} | %{
            @{'ObjectId'=$_.ObjectId;'DisplayName'=$_.DisplayName;}    
        })

        @{'ObjectId'=$objectId;'DisplayName'=$displayName;'Description'=$description;'Members'=$members;}
    })

    $updateAdGroups = @($currentAdGroups | ?{$AdGroups -and $AdGroups.DisplayName.Contains($_.DisplayName)})

    $createAdGroups = @($AdGroups | ?{!($updateAdGroups -and $updateAdGroups.DisplayName.Contains($_.DisplayName))} | %{
        $displayName = $_.DisplayName
        $description = $_.Description
        $members = @($_.Members | %{
            @{'ObjectId'='';'DisplayName'=$_;}    
        })
        @{'ObjectId'=$objectId;'DisplayName'=$displayName;'Description'=$description;'Members'=$members;}
    })

    $desiredAdGroups = @()
    $desiredAdGroups += $createAdGroups
    $desiredAdGroups += $updateAdGroups

    $desiredAdGroupResults = @(Get-TopologicalSortedAzureRmAdGroups -AzureRmAdGroups $desiredAdGroups) | %{
        $objectId = $_.ObjectId
        $displayName = $_.DisplayName
        $description = $_.Description
        $members = @($_.Members)

        if ($createAdGroups -and $createAdGroups.DisplayName.Contains($displayName)){
            $mailNickName = [guid]::NewGuid().Guid
            Write-Host "New-AzureADGroup -Description '$description' -DisplayName '$displayName' -MailNickName '$mailNickName' -MailEnabled `$false -SecurityEnabled `$true"
            $currentAdGroup = New-AzureADGroup -Description $description -DisplayName $displayName -MailNickName $mailNickName -MailEnabled $false -SecurityEnabled $true
            $_.ObjectId = $currentAdGroup.ObjectId

            $currentMembers = $members | %{
                $memberObjectId = $_.ObjectId
                $memberDisplayName = $_.DisplayName
                if (!$memberObjectId){
                    $_.ObjectId = Get-AzureADGroup -Searchstring $memberDisplayName | ?{ $_.DisplayName -eq $memberDisplayName } | %{ $_.ObjectId }
                    Write-Host "Add-AzureADGroupMember -ObjectId '$($currentAdGroup.ObjectId)' -RefObjectId '$($memberObjectId)'"
                    $result = Add-AzureADGroupMember -ObjectId $currentAdGroup.ObjectId -RefObjectId $memberObjectId
                }
                $_
            }
            $_.Members = $currentMembers
            $_
        } elseif ($updateAdGroups -and $updateAdGroups.DisplayName.Contains($displayName)) {
            $desiredAdGroup = $AdGroups | ?{$_.DisplayName -eq $displayName}
            if ($desiredAdGroup)
            {
                $desiredDescription = $desiredAdGroup.Description
                $desiredMembers = @($desiredAdGroup.Members)

                if ($desiredDescription -ne $description) {
                    Write-Host "Set-AzureADGroup -ObjectId '$objectId' -Description '$desiredDescription'"    
                    $result = Set-AzureADGroup -ObjectId $objectId -Description $desiredDescription
                }

                $currentMembers = @($members | %{
                    $memberObjectId = $_.ObjectId
                    $memberDisplayName = $_.DisplayName
                    if (!$memberObjectId){
                        #add
                        $_.ObjectId = Get-AzureADGroup -Searchstring $memberDisplayName | ?{ $_.DisplayName -eq $memberDisplayName } | %{ $_.ObjectId }
                        Write-Host "Add-AzureADGroupMember -ObjectId '$($currentAdGroup.ObjectId)' -RefObjectId '$memberObjectId'"
                        $result = Add-AzureADGroupMember -ObjectId $currentAdGroup.ObjectId -RefObjectId $memberObjectId
                        $_
                    } elseif ($desiredMembers -and $desiredMembers.Contains($memberDisplayName)) {
                        #update
                        $_
                    } else {
                        #delete
                        if ($DeleteUnknownAdGroupMembers) {
                            Write-Host "Remove-AzureADGroupMember -ObjectId '$($currentAdGroup.ObjectId)' -RefObjectId '$memberObjectId'"
                            $result = Remove-AzureADGroupMember -ObjectId $currentAdGroup.ObjectId -RefObjectId $memberObjectId
                        }
                    }
                })
                
                $_.Members = $currentMembers
                $_
            }
        }
    }

    if ($DeleteUnknownAdGroups) {
        $deleteAdGroupObjectIds = Get-TopologicalSortedAzureRmAdGroups -AzureRmAdGroups @($currentAdGroups | ?{!($AdGroups -and $AdGroups.DisplayName.Contains($_.DisplayName))}) | %{$_.ObjectId}
        [array]::Reverse($deleteAdGroupObjectIds)
        $deleteAdGroupObjectIds | %{
            Write-Host "Remove-AzureADGroup -ObjectId '$_'"
            $result = Remove-AzureADGroup -ObjectId $_
        }
    }

    $desiredAdGroupResults
}

function Get-TopologicalSortedAzureRmManagementGroups {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $AzureRmManagementGroups
    )

    $azureRmManagementGroupNames = @{} 
    $AzureRmManagementGroups | %{
        $key = $_.Name
        $value = $_.ParentId
        $azureRmManagementGroupNames[$key]=$value
    }
    $azureRmManagementGroupNames = Get-TopologicalSort -edgeList $azureRmManagementGroupNames | ?{$AzureRmManagementGroups.Name.Contains($_)}
  
    $topologicalSortedAzureRmManagementGroups = @()

    $azureRmManagementGroupNames | %{
        $managementGroupName = $_
        $topologicalSortedAzureRmManagementGroups += $AzureRmManagementGroups |? {$_.Name -eq $managementGroupName}
    }

    $topologicalSortedAzureRmManagementGroups
}

Function Set-DscManagementGroup {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $ManagementGroups,
        [Parameter(Mandatory = $false, Position = 1)]
        $DeleteUnknownManagementGroups = $false
    )

    $currentManagementGroups = @(Get-AzureRmManagementGroup | %{
        $name = $_.Name
        $displayName = $_.DisplayName
        $parentId = (Get-AzureRmManagementGroup -GroupName $name -Expand).ParentId
        #if ($parentId){
        #    $parentId = $parentId.TrimStart('/providers/Microsoft.Management/managementGroups/')
        #}
        @{'Name'=$name;'DisplayName'=$displayName;'ParentId'=$parentId;}
    })

    $rootManagementGroupName = $currentManagementGroups | ?{$null -eq $_.ParentId} | %{$_.Name}
    $updateManagementGroups = @($currentManagementGroups | ?{$null -ne $_.ParentId -and ($ManagementGroups -and $ManagementGroups.Name.Contains($_.Name))})
    
    $createManagementGroups = @($ManagementGroups | ?{!($updateManagementGroups -and $updateManagementGroups.Name.Contains($_.Name))} | %{
        $name = $_.Name
        $displayName = $_.DisplayName
        $parentId = $_.ParentId
        if ($parentId){
            $parentId = $parentId.TrimStart('/providers/Microsoft.Management/managementGroups/')
        } 
        
        if (!$parentId) {
            #Non specified parent id means root management group is parent
            $parentId = $rootManagementGroupName
        }
        @{'Name'=$name;'DisplayName'=$displayName;'ParentId'=$parentId;}
    })
    
    $desiredManagementGroups = @()
    $desiredManagementGroups += $createManagementGroups
    $desiredManagementGroups += $updateManagementGroups

    $desiredManagementGroupResults = @(Get-TopologicalSortedAzureRmManagementGroups -AzureRmManagementGroups $desiredManagementGroups) | %{
        $name = $_.Name
        $displayName = $_.DisplayName
        $parentId = $_.ParentId
        if ($parentId){
            $parentId = $parentId.TrimStart('/providers/Microsoft.Management/managementGroups/')
        } 
        if (!$parentId) {
            #Non specified parent id means root management group is parent
            $parentId = $rootManagementGroupName
        }

        if ($createManagementGroups -and $createManagementGroups.Name.Contains($name)){
            Write-Host "New-AzureRmManagementGroup -GroupName '$name' -DisplayName '$displayName' -ParentId '/providers/Microsoft.Management/managementGroups/$parentId'"
            $result = New-AzureRmManagementGroup -GroupName $name -DisplayName $displayName -ParentId "/providers/Microsoft.Management/managementGroups/$parentId"
            $_
        } elseif ($updateManagementGroups -and $updateManagementGroups.Name.Contains($name)) {
            $desiredManagementGroup = $ManagementGroups | ?{$_.Name -eq $name}
            if ($desiredManagementGroup)
            {
                $desiredDisplayName = $desiredManagementGroup.DisplayName
                $desiredParentId = $desiredManagementGroup.ParentId
                if ($desiredParentId){
                    $desiredParentId = $desiredParentId.TrimStart('/providers/Microsoft.Management/managementGroups/')
                } 
                if (!$desiredParentId) {
                    #Non specified parent id means root management group is parent
                    $desiredParentId = $rootManagementGroupName
                }
                if ($desiredDisplayName -ne $displayName -or $desiredParentId -ne $parentId) {
                    Write-Host "Update-AzureRmManagementGroup -GroupName '$name' -DisplayName '$desiredDisplayName' -ParentId '/providers/Microsoft.Management/managementGroups/$desiredParentId'"
                    $result = Update-AzureRmManagementGroup -GroupName $name -DisplayName $desiredDisplayName -ParentId "/providers/Microsoft.Management/managementGroups/$desiredParentId"
                }
                $_
            }
        } 
    }

    if ($DeleteUnknownManagementGroups) {
        $deleteManagementGroupNames = Get-TopologicalSortedAzureRmManagementGroups -AzureRmManagementGroups @($currentManagementGroups | ?{$null -ne $_.ParentId -and !($ManagementGroups -and $ManagementGroups.Name.Contains($_.Name))}) | %{$_.Name}
        [array]::Reverse($deleteManagementGroupNames)
        $deleteManagementGroupNames | %{
            Write-Host "Remove-AzureRmManagementGroup -GroupName '$_'"
            $result = Remove-AzureRmManagementGroup -GroupName $_
        }
    }

    $desiredManagementGroupResults
}

function Get-SubscriptionForManagementGroupHiearchy {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $ManagementGroupHiearchy
    )

    $subscriptions = @()
    $subscriptions += @($ManagementGroupHiearchy.Children | ?{$_.Type -eq '/subscriptions'} | %{$_.Id})
    $subscriptions += @($ManagementGroupHiearchy.Children | ?{$_.Type -eq '/providers/Microsoft.Management/managementGroups'} | %{ Get-SubscriptionForManagementGroupHiearchy -ManagementGroupHiearchy $_})
    $subscriptions
}

function Get-SubscriptionForTenants {
    @(Get-AzureRmSubscription | %{"/subscriptions/$($_.Id)"})
}

Function Set-DscRoleDefinition {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $RoleDefinitionPath,
        [Parameter(Mandatory = $false, Position = 1)]
        $DeleteUnknownRoleDefinition = $false
    )

    $RoleDefinitions = Get-ChildItem -Path $RoleDefinitionPath -Filter *.json | %{
        $name = $_.Basename
        $inputFileObject = [System.IO.File]::ReadAllLines($_.FullName) | ConvertFrom-Json
        if ($inputFileObject.IsCustom){
            $assignableScopes = @()

            #https://feedback.azure.com/forums/911473-azure-management-groups/suggestions/34391878-allow-custom-rbac-definitions-at-the-management-gr
            #Currently cannot be set to the root scope ("/") or a management group scope

            $inputFileObject.AssignableScopes | %{
                if (!$_){

                }
                if ($_ -eq '/') {
                    $assignableScopes += @(Get-SubscriptionForTenants)
                } elseif ($_.StartsWith('/providers/Microsoft.Management/managementGroups/')) {
                    $managementGroupHiearchy = Get-AzureRmManagementGroup -GroupName $ManagementGroup.TrimStart('/providers/Microsoft.Management/managementGroups/') -Expand -Recurse
                    $assignableScopes += @(Get-SubscriptionForManagementGroupHiearchy -ManagementGroupHiearchy $managementGroupHiearchy)
                } else {
                    $assignableScopes += @($_)
                }
            } 

            $inputFileObject.AssignableScopes = $assignableScopes

            $inputFile = $inputFileObject | ConvertTo-Json -Depth 99

            @{'Name'=$name;'InputFile'=$inputFile;}        
        }
    }

    #hack - cache issues hence the %{try{Get-AzureRmRoleDefinition -Id $_.Id}catch{}}
    $currentRoleDefinitions = @(Get-AzureRmRoleDefinition -Custom | %{try{$r=Get-AzureRmRoleDefinition -Id $_.Id -ErrorAction Stop;$r}catch{}} | %{
        $name = $_.Name
        $inputFile = $_ | ConvertTo-Json -Depth 99
        @{'Name'=$name;'InputFile'=$inputFile;}
    })

    #hack start - cache issues hence the double createRole check
    $updateRoleDefinitions = @($currentRoleDefinitions | ?{$RoleDefinitions -and $RoleDefinitions.Name.Contains($_.Name)})
    $createRoleDefinitions = @($RoleDefinitions | ?{!($updateRoleDefinitions -and $updateRoleDefinitions.Name.Contains($_.Name))})
    $currentRoleDefinitions += @($createRoleDefinitions | %{try{$r=Get-AzureRmRoleDefinition -Name $_.Name -ErrorAction Stop;$r}catch{}} | %{
        $name = $_.Name
        $inputFile = $_ | ConvertTo-Json -Depth 99
        @{'Name'=$name;'InputFile'=$inputFile;}
    })
    #hack stop - cache issues hence the double createRole check
    
    $updateRoleDefinitions = @($currentRoleDefinitions | ?{$RoleDefinitions -and $RoleDefinitions.Name.Contains($_.Name)})
    $createRoleDefinitions = @($RoleDefinitions | ?{!($updateRoleDefinitions -and $updateRoleDefinitions.Name.Contains($_.Name))})

    $desiredRoleDefinitions = @()
    $desiredRoleDefinitions += $createRoleDefinitions
    $desiredRoleDefinitions += $updateRoleDefinitions

    $desiredRoleDefinitionResults = $desiredRoleDefinitions | %{
        $name = $_.Name
        $inputFile = $_.InputFile

        if ($createRoleDefinitions -and $createRoleDefinitions.Name.Contains($name)){
            Write-Host @"
`$inputFile=@'
$inputFile
'@                    
New-AzureRmRoleDefinition -Role ([Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleDefinition](`$inputFile | ConvertFrom-Json))
"@
            $result = New-AzureRmRoleDefinition -Role ([Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleDefinition]($inputFile | ConvertFrom-Json))
            $_
        } elseif ($updateRoleDefinitions -and $updateRoleDefinitions.Name.Contains($name)) {
            $desiredRoleDefinition = $RoleDefinitions | ?{$_.Name -eq $name}
            if ($desiredRoleDefinition)
            {
                $desiredInputFileObject = $desiredRoleDefinition.InputFile | ConvertFrom-Json 
                $r = $desiredInputFileObject | Add-Member -MemberType noteProperty -name 'Id' -Value (($inputFile | ConvertFrom-Json).Id) 
                $desiredInputFile = [Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleDefinition]$desiredInputFileObject | ConvertTo-Json 
                
                if ($desiredInputFile -ne $inputFile) {
                    Write-Host @"
`$desiredInputFile=@'
$desiredInputFile
'@
`$inputFile=@'
$inputFile
'@
Set-AzureRmRoleDefinition -Role ([Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleDefinition](`$desiredInputFile | ConvertFrom-Json))
"@
                    $result = Set-AzureRmRoleDefinition -Role ([Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleDefinition]($desiredInputFile | ConvertFrom-Json))                }
                $_
            }
        }
    }

    if ($DeleteUnknownRoleDefinition) {
        $deleteRoleDefinitionNames = @($currentRoleDefinitions | ?{!($RoleDefinitions -and $RoleDefinitions.Name.Contains($_.Name))}) | %{$_.Name}
        $deleteRoleDefinitionNames | %{
            Write-Host "Remove-AzureRmRoleDefinition -Name '$_'"
            $result = Remove-AzureRmRoleDefinition -Name $_ -Force
        }
    }

    $desiredRoleDefinitionResults
}

Function Set-DscPolicyDefinition {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $PolicyDefinitionPath,
        [Parameter(Mandatory = $true, Position = 1)]
        $ManagementGroupName,
        [Parameter(Mandatory = $false, Position = 2)]
        $DeleteUnknownPolicyDefinition = $false
    )

    $PolicyDefinitions = Get-ChildItem -Path $PolicyDefinitionPath | ?{ $_.PSIsContainer -and (Test-Path -Path (Join-Path $_.FullName 'azurepolicy.json'))} | %{
        $inputFileObject = [System.IO.File]::ReadAllLines((Join-Path $_.FullName 'azurepolicy.json')) | ConvertFrom-Json
        if ($inputFileObject.Properties.policyType -ne 'BuiltIn'){
            $name = $inputFileObject.name
            if (!$name){
                $name = $_.Basename
            }
            $description = $inputFileObject.properties.description
            $displayName = $inputFileObject.properties.displayName
            $metadata = $inputFileObject.properties.metadata | ConvertTo-Json -Depth 99
            $policy = $inputFileObject.properties.policyRule | ConvertTo-Json -Depth 99
            $parameter = $inputFileObject.properties.parameters | ConvertTo-Json -Depth 99
 
            @{'Name'=$name;'Description'=$description;'DisplayName'=$displayName;'Metadata'=$metadata;'Policy'=$policy;'Parameter'=$parameter;}        
        }
    }

    #"Custom" flag does not seem to work hence filtering
    $currentPolicyDefinitions = @(Get-AzureRmPolicyDefinition -Custom -ManagementGroupName $ManagementGroupName | ?{$_.Properties.policyType -ne 'BuiltIn'} | %{
        $name = $_.Name
        $description = $_.properties.description
        $displayName = $_.properties.displayName
        $metadata = $_.properties.metadata | ConvertTo-Json -Depth 99
        $policy = $_.properties.policyRule | ConvertTo-Json -Depth 99
        $parameter = $_.properties.parameters | ConvertTo-Json -Depth 99

        @{'Name'=$name;'Description'=$description;'DisplayName'=$displayName;'Metadata'=$metadata;'Policy'=$policy;'Parameter'=$parameter;}
    })

    $updatePolicyDefinitions = @($currentPolicyDefinitions | ?{$PolicyDefinitions -and $PolicyDefinitions.Name.Contains($_.Name)})
    $createPolicyDefinitions = @($PolicyDefinitions | ?{!($updatePolicyDefinitions -and $updatePolicyDefinitions.Name.Contains($_.Name))})

    $desiredPolicyDefinitions = @()
    $desiredPolicyDefinitions += $createPolicyDefinitions
    $desiredPolicyDefinitions += $updatePolicyDefinitions

    $desiredPolicyDefinitionResults = $desiredPolicyDefinitions | %{
        $name = $_.Name
        $description = $_.Description
        $displayName = $_.DisplayName
        $metadata = $_.Metadata
        $policy = $_.Policy
        $parameter = $_.Parameter

        if ($createPolicyDefinitions -and $createPolicyDefinitions.Name.Contains($name)){
            Write-Host @"
`$metadata=@'
$metadata
'@
`$policy=@'
$policy
'@
`$parameter=@'
$parameter
'@
New-AzureRmPolicyDefinition -ManagementGroupName '$ManagementGroupName' -Name '$name' -DisplayName '$displayName' -Description '$description' -Metadata `$metadata -Policy `$policy -Parameter `$parameter
"@
            $result = New-AzureRmPolicyDefinition -ManagementGroupName $ManagementGroupName -Name $name -DisplayName $displayName -Description $description -Metadata $metadata -Policy $policy -Parameter $parameter
            $_
        } elseif ($updatePolicyDefinitions -and $updatePolicyDefinitions.Name.Contains($name)) {
            $desiredPolicyDefinition = $PolicyDefinitions | ?{$_.Name -eq $name}
            if ($desiredPolicyDefinition)
            {
                $desiredDescription = $desiredPolicyDefinition.Description
                $desiredDisplayName = $desiredPolicyDefinition.DisplayName
                $desiredMetadata = $desiredPolicyDefinition.Metadata
                $desiredPolicy = $desiredPolicyDefinition.Policy
                $desiredParameter = $desiredPolicyDefinition.Parameter
        
                if ($desiredDescription -ne $description -or $desiredDisplayName -ne $displayName -or $desiredMetadata -ne $metadata -or $desiredPolicy -ne $policy -or $desiredParameter -ne $parameter) {
                    Write-Host @"
`$metadata=@'
$desiredMetadata
'@
`$policy=@'
$desiredPolicy
'@
`$parameter=@'
$desiredParameter
'@
Set-AzureRmPolicyDefinition -ManagementGroupName '$ManagementGroupName' -Name '$name' -DisplayName '$desiredDisplayName' -Description '$desiredDescription' -Metadata `$metadata -Policy `$policy -Parameter `$parameter
"@
                    $result = Set-AzureRmPolicyDefinition -ManagementGroupName $ManagementGroupName -Name $name -DisplayName $desiredDisplayName -Description $desiredDescription -Metadata $desiredMetadata -Policy $desiredPolicy -Parameter $desiredParameter
                }
                $_
            }
        }
    }

    if ($DeleteUnknownPolicyDefinition) {
        $deletePolicyDefinitionNames = @($currentPolicyDefinitions | ?{!($PolicyDefinitions -and $PolicyDefinitions.Name.Contains($_.Name))}) | %{$_.Name}
        $deletePolicyDefinitionNames | %{
            Write-Host "Remove-AzureRmPolicyDefinition -ManagementGroupName '$ManagementGroupName' -Name '$_'"
            $result = Remove-AzureRmPolicyDefinition -ManagementGroupName $ManagementGroupName -Name $_ -Force
        }
    }

    $desiredPolicyDefinitionResults
}

Function Set-DscPolicySetDefinition {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $PolicySetDefinitionPath,
        [Parameter(Mandatory = $true, Position = 1)]
        $ManagementGroupName,
        [Parameter(Mandatory = $false, Position = 2)]
        $DeleteUnknownPolicySetDefinition = $false
    )

    $PolicySetDefinitions = Get-ChildItem -Path $PolicySetDefinitionPath | ?{ $_.PSIsContainer -and (Test-Path -Path (Join-Path $_.FullName 'azurepolicyset.json'))} | %{
        $inputFileObject = [System.IO.File]::ReadAllLines((Join-Path $_.FullName 'azurepolicyset.json')) | ConvertFrom-Json
        if ($inputFileObject.Properties.policyType -ne 'BuiltIn'){
            $name = $inputFileObject.name
            if (!$name){
                $name = $_.Basename
            }
            $description = $inputFileObject.properties.description
            $displayName = $inputFileObject.properties.displayName
            $metadata = $inputFileObject.properties.metadata | ConvertTo-Json -Depth 99
            $policyDefinitions = $inputFileObject.properties.policyDefinitions | %{
                if (!$_.policyDefinitionId.Contains('/')){
                    $_.policyDefinitionId = "/providers/Microsoft.Management/managementgroups/$($ManagementGroupName)/providers/Microsoft.Authorization/policyDefinitions/$($_.policyDefinitionId)"
                }
                $_
            } | ConvertTo-Json -Depth 99
            $parameter = $inputFileObject.properties.parameters | ConvertTo-Json -Depth 99
 
            @{'Name'=$name;'Description'=$description;'DisplayName'=$displayName;'Metadata'=$metadata;'PolicyDefinitions'=$policyDefinitions;'Parameter'=$parameter;}        
        }
    }

    #"Custom" flag does not seem to work hence filtering
    $currentPolicySetDefinitions = @(Get-AzureRmPolicySetDefinition -Custom -ManagementGroupName $ManagementGroupName | ?{$_.Properties.policyType -ne 'BuiltIn'} | %{
        $name = $_.Name
        $description = $_.properties.description
        $displayName = $_.properties.displayName
        $metadata = $_.properties.metadata | ConvertTo-Json -Depth 99
        $policyDefinitions = $_.properties.policyDefinitions | %{
            if (!$_.policyDefinitionId.Contains('/')){
                $_.policyDefinitionId = "/providers/Microsoft.Management/managementgroups/$($ManagementGroupName)/providers/Microsoft.Authorization/policyDefinitions/$($_.policyDefinitionId)"
            }
            $_
        } | ConvertTo-Json -Depth 99
        $parameter = $_.properties.parameters | ConvertTo-Json -Depth 99

        @{'Name'=$name;'Description'=$description;'DisplayName'=$displayName;'Metadata'=$metadata;'PolicyDefinitions'=$policyDefinitions;'Parameter'=$parameter;}
    })

    $updatePolicySetDefinitions = @($currentPolicySetDefinitions | ?{$PolicySetDefinitions -and $PolicySetDefinitions.Name.Contains($_.Name)})
    $createPolicySetDefinitions = @($PolicySetDefinitions | ?{!($updatePolicySetDefinitions -and $updatePolicySetDefinitions.Name.Contains($_.Name))})

    $desiredPolicySetDefinitions = @()
    $desiredPolicySetDefinitions += $createPolicySetDefinitions
    $desiredPolicySetDefinitions += $updatePolicySetDefinitions

    $desiredPolicySetDefinitionResults = $desiredPolicySetDefinitions | %{
        $name = $_.Name
        $description = $_.Description
        $displayName = $_.DisplayName
        $metadata = $_.Metadata
        $policyDefinitions = $_.PolicyDefinitions
        $parameter = $_.Parameter

        if ($createPolicySetDefinitions -and $createPolicySetDefinitions.Name.Contains($name)){
            Write-Host @"
`$metadata=@'
$metadata
'@
`$policyDefinitions=@'
$policyDefinitions
'@
`$parameter=@'
$parameter
'@
New-AzureRmPolicySetDefinition -ManagementGroupName '$ManagementGroupName' -Name '$name' -DisplayName '$displayName' -Description '$description' -Metadata `$metadata -PolicyDefinition `$policyDefinitions -Parameter `$parameter
"@
            $result = New-AzureRmPolicySetDefinition -ManagementGroupName $ManagementGroupName -Name $name -DisplayName $displayName -Description $description -Metadata $metadata -PolicyDefinition $policyDefinitions -Parameter $parameter
            $_
        } elseif ($updatePolicySetDefinitions -and $updatePolicySetDefinitions.Name.Contains($name)) {
            $desiredPolicySetDefinition = $PolicySetDefinitions | ?{$_.Name -eq $name}
            if ($desiredPolicySetDefinition)
            {
                $desiredDescription = $desiredPolicySetDefinition.Description
                $desiredDisplayName = $desiredPolicySetDefinition.DisplayName
                $desiredMetadata = $desiredPolicySetDefinition.Metadata
                $desiredPolicyDefinitions = $desiredPolicySetDefinition.PolicyDefinitions
                $desiredParameter = $desiredPolicySetDefinition.Parameter
        
                if ($desiredDescription -ne $description -or $desiredDisplayName -ne $displayName -or $desiredMetadata -ne $metadata -or $desiredPolicyDefinitions -ne $policyDefinitions -or $desiredParameter -ne $parameter) {
                    Write-Host @"
`$metadata=@'
$desiredMetadata
'@
`$policyDefinitions=@'
$desiredPolicyDefinitions
'@
`$parameter=@'
$desiredParameter
'@
Set-AzureRmPolicySetDefinition -ManagementGroupName '$ManagementGroupName' -Name '$name' -DisplayName '$desiredDisplayName' -Description '$desiredDescription' -Metadata `$metadata -PolicyDefinition `$policyDefinitions -Parameter `$parameter
"@
                    $result = Set-AzureRmPolicySetDefinition -ManagementGroupName $ManagementGroupName -Name $name -DisplayName $desiredDisplayName -Description $desiredDescription -Metadata $desiredMetadata -PolicyDefinition $desiredPolicyDefinitions -Parameter $desiredParameter
                }
                $_
            }
        }
    }

    if ($DeleteUnknownPolicySetDefinition) {
        $deletePolicySetDefinitionNames = @($currentPolicySetDefinitions | ?{!($PolicySetDefinitions -and $PolicySetDefinitions.Name.Contains($_.Name))}) | %{$_.Name}
        $deletePolicySetDefinitionNames | %{
            Write-Host "Remove-AzureRmPolicySetDefinition -ManagementGroupName '$ManagementGroupName' -Name '$_'"
            $result = Remove-AzureRmPolicySetDefinition -ManagementGroupName $ManagementGroupName -Name $_ -Force
        }
    }

    $desiredPolicySetDefinitionResults
}

function Get-RoleAssignmentFromConfig {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $Scope,
        [Parameter(Mandatory = $true, Position = 1)]
        $ConfigItem
    )

    $roleDefinitionName = $ConfigItem.RoleDefinitionName
    $canDelegate = $ConfigItem.CanDelegate
    $objectName = $ConfigItem.ObjectName
    $objectType = $ConfigItem.ObjectType
    $objectId = ''
    
    if ($objectType -eq "Group"){
        $group = Get-AzureRmADGroup -DisplayName $objectName
        if ($group){
            $objectId = $group.Id
        }
    } elseif ($objectType -eq "User") {
        $user = Get-AzureRmADUser -DisplayName $objectName
        if ($user){
            $objectId = $user.Id
        }
    } elseif ($objectType -eq "Application") {
        $application = Get-AzureRmADApplication -DisplayName $objectName
        if ($application){
            $objectId = $application.Id
        }
    }

    if ($objectId){
        @{'RoleDefinitionName'=$roleDefinitionName;'Scope'=$Scope;'CanDelegate'=$canDelegate;'ObjectId'=$objectId;}   
    }   
}

Function Set-DscRoleAssignment {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $RootRoleAssignments,
        [Parameter(Mandatory = $true, Position = 1)]
        $ManagementGroups,
        [Parameter(Mandatory = $false, Position = 2)]
        $DeleteUnknownRoleAssignment = $false
    )
    $RoleAssignments = $RootRoleAssignments | %{
        $scope = "/"
        Get-RoleAssignmentFromConfig -Scope $scope -ConfigItem $_
    }

    $RoleAssignments += $ManagementGroups | %{
        $ManagementGroupName = $_.Name
        $_.RoleAssignments | %{
            $scope = "/providers/Microsoft.Management/managementGroups/$ManagementGroupName"
            Get-RoleAssignmentFromConfig -Scope $scope -ConfigItem $_
        }  
        $_.Subscriptions | %{
            $subscriptionName = $_.Name
            $subscription = Get-AzureRmSubscription -SubscriptionName $subscriptionName
            $subscriptionId = $subscription.Id

            $_.RoleAssignments | %{
                $scope = "/subscriptions/$subscriptionId"
                Get-RoleAssignmentFromConfig -Scope $scope -ConfigItem $_
            }
        }
    }

    #Only deal with role assignments against root, management groups and subscriptions. Role assignments directly to providers should be abstracted by RoleDefinition applied at management group or subscription
    $currentRoleAssignments = @(Get-AzureRmRoleAssignment | ?{$_.Scope -eq '/' -or $_.Scope.StartsWith('/providers/Microsoft.Management/managementGroups/') -or $_.Scope.StartsWith('/subscriptions/')} %{
        $scope = $_.Scope
        $roleDefinitionName = $_.RoleDefinitionName
        $objectId = $_.ObjectId
        $canDelegate = $_.CanDelegate
        
        @{'Scope'=$scope;'RoleDefinitionName'=$roleDefinitionName;'ObjectId'=$objectId;'CanDelegate'=$canDelegate;} 
    })

    $updateRoleAssignments = @($currentRoleAssignments | %{
        $scope = $_.Scope
        $roleDefinitionName = $_.RoleDefinitionName
        $objectId = $_.ObjectId

        if ($RoleAssignments | ?{$_.Scope -eq $scope -and $_.RoleDefinitionName -eq $roleDefinitionName -and $_.ObjectId -eq $objectId}){
           $_ 
        }
    })

    $createRoleAssignments = @($RoleAssignments | %{
        $scope = $_.Scope
        $roleDefinitionName = $_.RoleDefinitionName
        $objectId = $_.ObjectId

        if (!($updateRoleAssignments | ?{$_.Scope -eq $scope -and $_.RoleDefinitionName -eq $roleDefinitionName -and $_.ObjectId -eq $objectId})){
            $_ 
         }
    })
    
    $desiredRoleAssignments = @()
    $desiredRoleAssignments += $createRoleAssignments
    $desiredRoleAssignments += $updateRoleAssignments

    $desiredRoleAssignmentResults = $desiredRoleAssignments | %{
        $scope = $_.Scope
        $roleDefinitionName = $_.RoleDefinitionName
        $objectId = $_.ObjectId
        $canDelegate = $_.CanDelegate
   
        if ($createRoleAssignments | ?{$_.Scope -eq $scope -and $_.RoleDefinitionName -eq $roleDefinitionName -and $_.ObjectId -eq $objectId}){
            Write-Host "New-AzureRmRoleAssignment -Scope '$scope' -RoleDefinitionName '$roleDefinitionName' -ObjectId '$objectId' -AllowDelegation:`$$canDelegate "
            $result = New-AzureRmRoleAssignment -Scope $scope -RoleDefinitionName $roleDefinitionName -ObjectId $objectId -AllowDelegation:$canDelegate
            $_
        } elseif ($updateRoleAssignments | ?{$_.Scope -eq $scope -and $_.RoleDefinitionName -eq $roleDefinitionName -and $_.ObjectId -eq $objectId}) {
            $desiredRoleAssignment = $RoleAssignments | ?{$_.Scope -eq $scope -and $_.RoleDefinitionName -eq $roleDefinitionName -and $_.ObjectId -eq $objectId}
            if ($desiredRoleAssignment)
            {
                $desiredScope = $_.Scope
                $desiredRoleDefinitionName = $_.RoleDefinitionName
                $desiredObjectId = $_.ObjectId
                $desiredCanDelegate = $_.CanDelegate
                
                if ($desiredCanDelegate -ne $canDelegate) {
                    Write-Host @"
Get-AzureRmRoleAssignment -Scope '$desiredScope' -RoleDefinitionName '$desiredRoleDefinitionName' -ObjectId '$desiredObjectId' | 
?{`$_.Scope -eq '$desiredScope' -and `$_.RoleDefinitionName -eq '$desiredRoleDefinitionName' -and `$_.ObjectId -eq '$desiredObjectId'} |
Remove-AzureRmRoleAssignment

New-AzureRmRoleAssignment -Scope '$desiredScope' -RoleDefinitionName '$desiredRoleDefinitionName' -ObjectId '$desiredObjectId' -AllowDelegation:`$$desiredCanDelegate 
"@
                    #Scope and ObjectId are not honoured as filters :<
                    $result = Get-AzureRmRoleAssignment -Scope $desiredScope -RoleDefinitionName $desiredRoleDefinitionName -ObjectId $desiredObjectId | 
                    ?{$_.Scope -eq $desiredScope -and $_.RoleDefinitionName -eq $desiredRoleDefinitionName -and $_.ObjectId -eq $desiredObjectId} |
                    Remove-AzureRmRoleAssignment 

                    $result = New-AzureRmRoleAssignment -Scope '$desiredScope' -RoleDefinitionName '$desiredRoleDefinitionName' -ObjectId '$desiredObjectId' -AllowDelegation:`$$desiredCanDelegate

                    $_
                }
            }
        }
    }

    if ($DeleteUnknownRoleAssignment) {
        @($currentRoleAssignments | %{
            $scope = $_.Scope
            $roleDefinitionName = $_.RoleDefinitionName
            $objectId = $_.ObjectId
    
            if (!($RoleAssignments | ?{$_.Scope -eq $scope -and $_.RoleDefinitionName -eq $roleDefinitionName -and $_.ObjectId -eq $objectId})){
                Write-Host @"
Get-AzureRmRoleAssignment -Scope '$scope' -RoleDefinitionName '$roleDefinitionName' -ObjectId '$objectId' | 
?{`$_.Scope -eq '$scope' -and `$_.RoleDefinitionName -eq '$roleDefinitionName' -and `$_.ObjectId -eq '$objectId'} |
Remove-AzureRmRoleAssignment
"@
                #Scope and ObjectId are not honoured as filters :<
                $result = Get-AzureRmRoleAssignment -Scope $scope -RoleDefinitionName $roleDefinitionName -ObjectId $objectId | 
                ?{$_.Scope -eq $scope -and $_.RoleDefinitionName -eq $roleDefinitionName -and $_.ObjectId -eq $objectId} |
                Remove-AzureRmRoleAssignment 
            }
        })
    }

    $desiredRoleAssignmentResults
}

Function Set-DscPolicyAssignment {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $ManagementGroups
    )
}

Function Set-DscPolicySetAssignment {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $ManagementGroups
    )
}

$DesiredState = [System.IO.File]::ReadAllLines((Resolve-Path 'DesiredState.json')) | ConvertFrom-Json

$AdGroups = $DesiredState.AdGroups

$ManagementGroups = $DesiredState.ManagementGroups
$ManagementGroups = $ManagementGroups | %{
    if (!$_.ParentId.Contains('/')){
        $_.ParentId = $parentIdPrefix + $_.ParentId
    }
    $_
}

Connect-AzureRmAccount -Credential $tenantAdminCredential -Environment $rootEnvironment
Connect-AzureAD -Credential $tenantAdminCredential -AzureEnvironmentName $rootEnvironment

#Create definitions at root, then all management groups can apply them at any level

$AdGroups = Set-DscAdGroup -AdGroups $AdGroups
$ManagementGroups = Set-DscManagementGroup -ManagementGroups $ManagementGroups
$RoleDefinitions = Set-DscRoleDefinition -RoleDefinitionPath (Resolve-Path 'RoleDefinitions')
$PolicyDefinitions = Set-DscPolicyDefinition -ManagementGroupName $tenantId -PolicyDefinitionPath (Resolve-Path 'PolicyDefinitions')
$PolicySetDefinitions = Set-DscPolicySetDefinition -ManagementGroupName $tenantId -PolicySetDefinitionPath (Resolve-Path 'PolicySetDefinitions')

#Create blue print at root, then all management groups can apply them at any level
#Resource Manager templates
#https://www.youtube.com/watch?v=SMORUIPhKd8&feature=youtu.be
#BluePrintDefinitions

#Create subscription and assign owner
#https://docs.microsoft.com/en-us/azure/azure-resource-manager/programmatically-create-subscription?tabs=azure-powershell
#https://docs.microsoft.com/en-us/powershell/module/azurerm.subscription/new-azurermsubscription?view=azurermps-6.10.0
#Set-AzureSubscription
#Get-AzureSubscription

#Add subscription to management group
#$ManagementGroupName = "ProductionHub1LOB2CICDBYOP"
#$SubscriptionId = "87c5bf6c-dcba-43d2-bf32-6f16f072b472"
#New-AzureRmManagementGroupSubscription -GroupName $ManagementGroupName -SubscriptionId $SubscriptionId

#Add role to management group or subscription
#New-AzureRmRoleAssignment
#$EnvironmentProvisioningManagementGroupADGroup = Get-AzureRMADGroup -SearchString "Environment Provisioning"
$RoleAssignments = Set-DscRoleAssignment -ManagementGroups $ManagementGroups

#Add policy to management group or subscription
#New-AzureRmPolicyAssignment -PolicyDefinition
$PolicyAssignments = Set-DscPolicyAssignment -ManagementGroups $ManagementGroups

#Add policy set to management group or subscription
#New-AzureRmPolicyAssignment -PolicySetDefinition
$PolicySetAssignments = Set-DscPolicySetAssignment -ManagementGroups $ManagementGroups

#BluePrintAssignments

#https://docs.microsoft.com/en-us/rest/api/policy-insights/
#Do this to show the number of non complaint resources
#https://docs.microsoft.com/en-us/azure/governance/policy/assign-policy-powershell







#Add role to management group
#$EnvironmentProvisioningManagementGroupADGroup = Get-AzureRMADGroup -SearchString "Environment Provisioning"

#$ProductionManagementGroupName = "Production"
#$ProductionManagementGroupId = $parentIdPrefix + $ProductionManagementGroupName
#New-AzureRmRoleAssignment -ObjectId $EnvironmentProvisioningManagementGroupADGroup.ObjectId -RoleDefinitionName "Reader" -Scope $ProductionManagementGroupId

#$DevTestManagementGroupName = "DevTest"
#$DevTestManagementGroupId = $parentIdPrefix + $DevTestManagementGroupName
#New-AzureRmRoleAssignment -ObjectId $EnvironmentProvisioningManagementGroupADGroup.ObjectId -RoleDefinitionName "Reader" -Scope $ProductionManagementGroupId

#$ManagementGroupName = "ProductionHub1LOB2CICD"
#$ManagementGroupId = $parentIdPrefix + $ManagementGroupName
#New-AzureRmRoleAssignment -ObjectId $EnvironmentProvisioningManagementGroupADGroup.ObjectId -RoleDefinitionName "Owner" -Scope $ManagementGroupId

#$BYOPManagementGroupName = $ManagementGroupName + "BYOP"
#$BYOPManagementGroupId = $parentIdPrefix + $BYOPManagementGroupName
#$SubscriptionId = "87c5bf6c-dcba-43d2-bf32-6f16f072b472"
#$EnvironmentAdminsManagementGroupADGroup = Get-AzureRMADGroup -SearchString "$BYOPManagementGroupName - Admins"
#$EnvironmentDevelopersManagementGroupADGroup = Get-AzureRMADGroup -SearchString "$BYOPManagementGroupName - Developers"
#New-AzureRmRoleAssignment -ObjectId $EnvironmentAdminsManagementGroupADGroup.ObjectId -RoleDefinitionName "Resource Policy Contributor" -Scope $BYOPManagementGroupId
#New-AzureRmRoleAssignment -ObjectId $EnvironmentAdminsManagementGroupADGroup.ObjectId -RoleDefinitionName "Management Group Reader" -Scope $BYOPManagementGroupId
#New-AzureRmRoleAssignment -ObjectId $EnvironmentAdminsManagementGroupADGroup.ObjectId -RoleDefinitionName "Owner" -Scope $SubscriptionGroupId
#New-AzureRmRoleAssignment -ObjectId $EnvironmentDevelopersManagementGroupADGroup.ObjectId -RoleDefinitionName "Management Group Reader" -Scope $BYOPManagementGroupId
#New-AzureRmRoleAssignment -ObjectId $EnvironmentDevelopersManagementGroupADGroup.ObjectId -RoleDefinitionName "Reader" -Scope $SubscriptionGroupId



