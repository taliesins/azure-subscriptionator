$ErrorActionPreference = "Stop"

function Test-JsonSchema([Parameter(Mandatory)][String] $Json, [Parameter(Mandatory)][String] $SchemaJson) {
    if ($PSVersionTable.CLRVersion.Major -lt 4) { 
        $dotNetType = "net35"
    } elseif ($PSVersionTable.CLRVersion.Major -gt 4) {
        $dotNetType = "netstandard2.0"
    } else {
        $dotNetType = "net40"
    }

    $NewtonsoftJsonPath = Resolve-Path -Path "modules\newtonsoft.json.11.0.2\lib\$($dotNetType)\Newtonsoft.Json.dll"
    try{
        if (Get-Item ([Newtonsoft.Json.Linq.JToken].Assembly.Location).VersionInfo.ProductVersion -ne '11.0.2') {
            Add-Type -Path $NewtonsoftJsonPath -Force
        }
    } catch{
        try
        {
            Add-Type -Path $NewtonsoftJsonPath
        }
        catch [System.Reflection.ReflectionTypeLoadException]
        {
            Write-Host "Message: $($_.Exception.Message)"
            Write-Host "StackTrace: $($_.Exception.StackTrace)"
            Write-Host "LoaderExceptions: $($_.Exception.LoaderExceptions)"
        }
    }

    $NewtonsoftJsonSchemaPath = Resolve-Path -Path "modules\newtonsoft.json.schema.3.0.10\lib\$($dotNetType)\Newtonsoft.Json.Schema.dll"
    try{
        if (Get-Item ([Newtonsoft.Json.Schema.JSchema].Assembly.Location).VersionInfo.ProductVersion -ne '3.0.10'){
            Add-Type -Path $NewtonsoftJsonSchemaPath
        }
    } catch{
        try
        {
            Add-Type -Path $NewtonsoftJsonSchemaPath
        }
        catch [System.Reflection.ReflectionTypeLoadException]
        {
            Write-Host "Message: $($_.Exception.Message)"
            Write-Host "StackTrace: $($_.Exception.StackTrace)"
            Write-Host "LoaderExceptions: $($_.Exception.LoaderExceptions)"
        }
    }

    try{
        if (-not [Validator]){}
    } catch{
        $source = @'
    public class Validator
    {
        public static System.Collections.Generic.IList<string> Validate(string tokenJson, string schemaJson)
        {
            Newtonsoft.Json.Linq.JToken token = Newtonsoft.Json.Linq.JToken.Parse(tokenJson);
            Newtonsoft.Json.Schema.JSchema schema = Newtonsoft.Json.Schema.JSchema.Parse(schemaJson);

            System.Collections.Generic.IList<string> messages;
            Newtonsoft.Json.Schema.SchemaExtensions.IsValid(token, schema, out messages);
            return messages;
        }
    }
'@
        Add-Type -TypeDefinition $source -ReferencedAssemblies $NewtonsoftJsonPath,$NewtonsoftJsonSchemaPath
    }

    $ErrorMessages = [Validator]::Validate($Json, $SchemaJson)
    return $ErrorMessages
}

function Format-Json([Parameter(Mandatory, ValueFromPipeline)][String] $json) {
    $indent = 0;
    $updatedJson = $json
    $updatedJson = $updatedJson -replace "\\u003c","<"
    $updatedJson = $updatedJson -replace "\\u003e",">"
    $updatedJson = $updatedJson -replace "\\u0027","'"
    $updatedJsonLines = $updatedJson -Split '\n'
    
    ($updatedJsonLines | ?{$_} | %{
        $withoutStuffInQuotes = $_ -replace '"([^"\\]*(\\.[^"\\]*)*)"', ""

        if ($withoutStuffInQuotes -match '[\}\]]') {
          # This line contains  ] or }, decrement the indentation level
          $indent--
        }

        $line = (' ' * $indent * 2) + $_.TrimStart()
        $line = $line -replace '"([^"\\]*(\\.[^"\\]*)*)"\s*:\s*', '"$1" : '

        if ($withoutStuffInQuotes -match '[\{\[]') {
          # This line contains [ or {, increment the indentation level
          $indent++
        }
        $line
    }) -Join "`n"
}

function Format-PolicyFiles([string]$Path){
    Push-Location -Path $Path
    try{
        $azurePolicyPaths = Get-ChildItem PolicyDefinitions | ?{ $_.PSIsContainer } | %{Join-Path -Path $_.FullName -ChildPath 'azurepolicy.json'} | ?{ Test-Path $_}
        $azurePolicyPaths | %{
            $azurePolicyPath = $_
            $azurePolicy = ([System.IO.File]::ReadAllText($azurePolicyPath)) | ConvertFrom-Json
            $azurePolicyJson = ConvertTo-Json $azurePolicy -Depth 99 | Format-Json
            [System.IO.File]::WriteAllText($azurePolicyPath, $azurePolicyJson)

            $azurePolicyParameterPath = Join-Path -Path (Split-Path $azurePolicyPath -Parent) -ChildPath 'azurepolicy.parameters.json'  
            $azurePolicyParameterJson = ConvertTo-Json $azurePolicy.properties.parameters -Depth 99 | Format-Json
            [System.IO.File]::WriteAllText($azurePolicyParameterPath, $azurePolicyParameterJson)

            $azurePolicyPolicyRulePath = Join-Path -Path (Split-Path $azurePolicyPath -Parent) -ChildPath 'azurepolicy.rules.json'
            $azurePolicyPolicyRuleJson =  ConvertTo-Json $azurePolicy.properties.policyRule -Depth 99 | Format-Json
            [System.IO.File]::WriteAllText($azurePolicyPolicyRulePath, $azurePolicyPolicyRuleJson)
        }
    } finally {
        Pop-Location
    }
}

function Format-PolicySetFiles([string]$Path, [string]$ManagementGroupName){
    Push-Location -Path $Path
    try{
        $azurePolicySetPaths = Get-ChildItem PolicySetDefinitions | ?{ $_.PSIsContainer } | %{Join-Path -Path $_.FullName -ChildPath 'azurepolicyset.json'} | ?{ Test-Path $_}
        $azurePolicySetPaths | %{
            $azurePolicySetPath = $_
            $azurePolicySet = ([System.IO.File]::ReadAllText($azurePolicySetPath)) -replace "/providers/Microsoft.Management/managementgroups/([^/]*)/providers/Microsoft.Authorization/policyDefinitions/", "/providers/Microsoft.Management/managementgroups/$($ManagementGroupName)/providers/Microsoft.Authorization/policyDefinitions/" | ConvertFrom-Json
            $azurePolicySetJson = ConvertTo-Json $azurePolicySet -Depth 99 | Format-Json
            [System.IO.File]::WriteAllText($azurePolicySetPath, $azurePolicySetJson)

            $azurePolicyParameterPath = Join-Path -Path (Split-Path $azurePolicySetPath -Parent) -ChildPath 'azurepolicyset.parameters.json'  
            $azurePolicyParameterJson = ConvertTo-Json $azurePolicySet.properties.parameters -Depth 99 | Format-Json
            [System.IO.File]::WriteAllText($azurePolicyParameterPath, $azurePolicyParameterJson)

            $azurePolicyPolicyDefinitionPath = Join-Path -Path (Split-Path $azurePolicySetPath -Parent) -ChildPath 'azurepolicyset.definitions.json'
            $azurePolicyPolicyDefinitionJson =  ConvertTo-Json $azurePolicySet.properties.policyDefinitions -Depth 99 | Format-Json
            [System.IO.File]::WriteAllText($azurePolicyPolicyDefinitionPath, $azurePolicyPolicyDefinitionJson)
        }
    } finally {
        Pop-Location
    }
}

function Format-BlueprintFiles([string]$Path, [string]$ManagementGroupName){
    Push-Location -Path $Path
    try{
        $blueprintPaths = Get-ChildItem Blueprints | ?{ $_.PSIsContainer } | %{Join-Path -Path $_.FullName -ChildPath 'azureblueprint.json'} | ?{ Test-Path $_}
        $blueprintPaths | %{
            $blueprintPath = $_
            $blueprint = ([System.IO.File]::ReadAllText($blueprintPath)) -replace "/providers/Microsoft.Management/managementgroups/([^/]*)/providers/Microsoft.Blueprint/blueprints/", "/providers/Microsoft.Management/managementgroups/$($ManagementGroupName)/providers/Microsoft.Blueprint/blueprints/" | ConvertFrom-Json
            $blueprintJson = ConvertTo-Json $blueprint -Depth 99 | Format-Json
            [System.IO.File]::WriteAllText($blueprintPath, $blueprintJson)

            $blueprintParameterPath = Join-Path -Path (Split-Path $blueprintPath -Parent) -ChildPath 'azureblueprint.parameters.json'  
            $blueprintParameterJson = ConvertTo-Json $blueprint.properties.parameters -Depth 99 | Format-Json
            [System.IO.File]::WriteAllText($blueprintParameterPath, $blueprintParameterJson)

            $blueprintResourceGroupPath = Join-Path -Path (Split-Path $blueprintPath -Parent) -ChildPath 'azureblueprint.resourcegroups.json'
            $blueprintResourceGroupJson =  ConvertTo-Json $blueprint.properties.resourceGroups -Depth 99 | Format-Json
            [System.IO.File]::WriteAllText($blueprintResourceGroupPath, $blueprintResourceGroupJson)

            $blueprintArtifactPaths = Get-ChildItem (Split-Path $blueprintPath) | ?{ $_.PSIsContainer } | %{Join-Path -Path $_.FullName -ChildPath 'azureblueprintartifact.json'} | ?{ Test-Path $_}
            $blueprintArtifactPaths | %{
                $blueprintArtifactPath = $_
                $blueprintArtifact = ([System.IO.File]::ReadAllText($blueprintArtifactPath)) -replace "/providers/Microsoft.Management/managementgroups/([^/]*)/providers/Microsoft.Blueprint/blueprints/", "/providers/Microsoft.Management/managementgroups/$($ManagementGroupName)/providers/Microsoft.Blueprint/blueprints/" | ConvertFrom-Json
                $blueprintArtifactJson = ConvertTo-Json $blueprintArtifact -Depth 99 | Format-Json
                [System.IO.File]::WriteAllText($blueprintArtifactPath, $blueprintArtifactJson)
            }
        }
    } finally {
        Pop-Location
    }
}

$currentWorkingDirectory = $PWD.Path
$configPath = Join-Path -Path $currentWorkingDirectory -ChildPath 'Config.json'
$configJson = [System.IO.File]::ReadAllText($configPath)
$configSchemaPath = Join-Path -Path $currentWorkingDirectory -ChildPath 'Config.Schema.json'
$configSchemaJson = [System.IO.File]::ReadAllText($configSchemaPath)

$errorMessages = Test-JsonSchema -Json $configJson -SchemaJson $configSchemaJson
$isValid = $errorMessages.Count -eq 0

if (!$isValid){
    foreach ($errorMessage in $errorMessages) {
        write-host $errorMessage -foregroundcolor "red"
    }

    throw "Schema is valid: $isValid"
    exit 1
}

$config = $configJson | ConvertFrom-Json
$definitionManagementGroupName=$config.Tenant.DefinitionManagementGroup
if (!$definitionManagementGroupName){
    $definitionManagementGroupName = $config.Tenant.Id
}

$desiredStatePath = Join-Path -Path $currentWorkingDirectory -ChildPath 'DesiredState.json'
$desiredStateJson = [System.IO.File]::ReadAllText($desiredStatePath)
$desiredStateSchemaPath = Join-Path -Path $currentWorkingDirectory -ChildPath 'DesiredState.Schema.json'
$desiredStateSchemaJson = [System.IO.File]::ReadAllText($desiredStateSchemaPath)
$errorMessages = Test-JsonSchema -Json $desiredStateJson -SchemaJson $desiredStateSchemaJson
$isValid = $errorMessages.Count -eq 0

if (!$isValid){
    foreach ($errorMessage in $errorMessages) {
        write-host $errorMessage -foregroundcolor "red"
    }

    throw "Schema is valid: $isValid"
    exit 1
}

Write-Host 'Formatting policies'
Format-PolicyFiles -Path $currentWorkingDirectory

Write-Host 'Formatting policy sets'
Format-PolicySetFiles -Path $currentWorkingDirectory -ManagementGroupName $definitionManagementGroupName

Write-Host 'Formatting blueprints'
Format-BlueprintFiles -Path $currentWorkingDirectory -ManagementGroupName $definitionManagementGroupName
