$azurePolicyPaths = Get-ChildItem PolicyDefinitions | ?{ $_.PSIsContainer } | %{Join-Path -Path $_.FullName -ChildPath 'azurepolicy.json'} | ?{ Test-Path $_}

$azurePolicyPaths | %{
    $azurePolicyJson = [System.IO.File]::ReadAllLines($_) | ConvertFrom-Json

    $azurePolicyParameterPath = Join-Path -Path (Split-Path $_ -Parent) -ChildPath 'azurepolicy.parameters.json'  
    $azurePolicyParameterJson = $azurePolicyJson.properties.parameters | ConvertTo-Json -Depth 99
    [System.IO.File]::WriteAllLines($azurePolicyParameterPath, $azurePolicyParameterJson)

    $azurePolicyPolicyRulePath = Join-Path -Path (Split-Path $_ -Parent) -ChildPath 'azurepolicy.rules.json'
    $azurePolicyPolicyRuleJson =  $azurePolicyJson.properties.policyRule | ConvertTo-Json -Depth 99
    [System.IO.File]::WriteAllLines($azurePolicyPolicyRulePath, $azurePolicyPolicyRuleJson)
}

$azurePolicySetPaths = Get-ChildItem PolicySetDefinitions | ?{ $_.PSIsContainer } | %{Join-Path -Path $_.FullName -ChildPath 'azurepolicyset.json'} | ?{ Test-Path $_}

$azurePolicySetPaths | %{
    $azurePolicySetJson = [System.IO.File]::ReadAllLines($_) | ConvertFrom-Json

    $azurePolicyParameterPath = Join-Path -Path (Split-Path $_ -Parent) -ChildPath 'azurepolicyset.parameters.json'  
    $azurePolicyParameterJson = $azurePolicySetJson.properties.parameters | ConvertTo-Json -Depth 99
    [System.IO.File]::WriteAllLines($azurePolicyParameterPath, $azurePolicyParameterJson)

    $azurePolicyPolicyDefinitionPath = Join-Path -Path (Split-Path $_ -Parent) -ChildPath 'azurepolicyset.definitions.json'
    $azurePolicyPolicyDefinitionJson =  $azurePolicySetJson.properties.policyDefinitions | ConvertTo-Json -Depth 99
    [System.IO.File]::WriteAllLines($azurePolicyPolicyDefinitionPath, $azurePolicyPolicyDefinitionJson)
}
