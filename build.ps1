$ErrorActionPreference = "Stop"

function Test-JsonSchema([Parameter(Mandatory)][String] $Json, [Parameter(Mandatory)][String] $SchemaJson) {
    $NewtonsoftJsonPath = Resolve-Path -Path 'modules\Newtonsoft.Json.dll'
    try{
        if (-not [Newtonsoft.Json.Linq.JToken]){}
    } catch{
        Add-Type -Path $NewtonsoftJsonPath
    }

    $NewtonsoftJsonSchemaPath = Resolve-Path -Path "modules\Newtonsoft.Json.Schema.dll"
    try{
        if (-not [Newtonsoft.Json.Schema.JSchema]){}
    } catch{
        Add-Type -Path $NewtonsoftJsonSchemaPath
    }

    try{
        if (-not [Validator]){}
    } catch{
        $source = @'
    public class Validator
    {
        public static System.Collections.Generic.IList<string> Validate(Newtonsoft.Json.Linq.JToken token, Newtonsoft.Json.Schema.JSchema schema)
        {
            System.Collections.Generic.IList<string> messages;
            Newtonsoft.Json.Schema.SchemaExtensions.IsValid(token, schema, out messages);
            return messages;
        }
    }
'@
        Add-Type -TypeDefinition $source -ReferencedAssemblies $NewtonsoftJsonPath,$NewtonsoftJsonSchemaPath
    }

    $Token = [Newtonsoft.Json.Linq.JToken]::Parse($Json)
    $Schema = [Newtonsoft.Json.Schema.JSchema]::Parse($SchemaJson)

    $ErrorMessages = [Validator]::Validate($Token, $Schema)
    return $ErrorMessages
}

function Format-Json([Parameter(Mandatory, ValueFromPipeline)][String] $json) {
    $indent = 0;
    ($json -replace "\\u003c","<" -replace "\\u003e",">" -replace "\\u0027","'" -Split '\n' |
      % {
        if ($_ -match '[\}\]]') {
          # This line contains  ] or }, decrement the indentation level
          $indent--
        }
        $line = (' ' * $indent * 2) + $_.TrimStart().Replace(':  ', ': ')
        if ($_ -match '[\{\[]') {
          # This line contains [ or {, increment the indentation level
          $indent++
        }
        $line
    }) -Join "`n"
}

$Json = [IO.File]::ReadAllText('DesiredState.json')
$SchemaJson = [IO.File]::ReadAllText('DesiredState.Schema.json')
$ErrorMessages = Test-JsonSchema -Json $Json -SchemaJson $SchemaJson

$IsValid = $ErrorMessages.Count -eq 0

if (!$IsValid){
    write-host "Schema is valid: $IsValid" -foregroundcolor "white"

    foreach ($ErrorMessage in $ErrorMessages) {
        write-host $ErrorMessage -foregroundcolor "red"
    }
} else {
    $azureDefinitionManagementGroup='1931b7d3-bd07-4b36-9814-adf4ad406860'
    $azurePolicyPaths = Get-ChildItem PolicyDefinitions | ?{ $_.PSIsContainer } | %{Join-Path -Path $_.FullName -ChildPath 'azurepolicy.json'} | ?{ Test-Path $_}

    $azurePolicyPaths | %{
        $azurePolicyPath = $_
        $azurePolicy = ([System.IO.File]::ReadAllLines($azurePolicyPath)) | ConvertFrom-Json
        $azurePolicyJson = $azurePolicy | ConvertTo-Json -Depth 99 | Format-Json
        [System.IO.File]::WriteAllLines($azurePolicyPath, $azurePolicyJson)

        $azurePolicyParameterPath = Join-Path -Path (Split-Path $azurePolicyPath -Parent) -ChildPath 'azurepolicy.parameters.json'  
        $azurePolicyParameterJson = $azurePolicy.properties.parameters | ConvertTo-Json -Depth 99 | Format-Json
        [System.IO.File]::WriteAllLines($azurePolicyParameterPath, $azurePolicyParameterJson)

        $azurePolicyPolicyRulePath = Join-Path -Path (Split-Path $azurePolicyPath -Parent) -ChildPath 'azurepolicy.rules.json'
        $azurePolicyPolicyRuleJson =  $azurePolicy.properties.policyRule | ConvertTo-Json -Depth 99 | Format-Json
        [System.IO.File]::WriteAllLines($azurePolicyPolicyRulePath, $azurePolicyPolicyRuleJson)
    }

    $azurePolicySetPaths = Get-ChildItem PolicySetDefinitions | ?{ $_.PSIsContainer } | %{Join-Path -Path $_.FullName -ChildPath 'azurepolicyset.json'} | ?{ Test-Path $_}

    $azurePolicySetPaths | %{
        $azurePolicySetPath = $_
        $azurePolicySet = ([System.IO.File]::ReadAllLines($azurePolicySetPath)) -replace "/providers/Microsoft.Management/managementgroups/([^/]*)/providers/Microsoft.Authorization/policyDefinitions/", "/providers/Microsoft.Management/managementgroups/$($azureDefinitionManagementGroup)/providers/Microsoft.Authorization/policyDefinitions/" | ConvertFrom-Json
        $azurePolicySetJson = $azurePolicySet | ConvertTo-Json -Depth 99 | Format-Json
        [System.IO.File]::WriteAllLines($azurePolicySetPath, $azurePolicySetJson)

        $azurePolicyParameterPath = Join-Path -Path (Split-Path $azurePolicySetPath -Parent) -ChildPath 'azurepolicyset.parameters.json'  
        $azurePolicyParameterJson = $azurePolicySet.properties.parameters | ConvertTo-Json -Depth 99 | Format-Json
        [System.IO.File]::WriteAllLines($azurePolicyParameterPath, $azurePolicyParameterJson)

        $azurePolicyPolicyDefinitionPath = Join-Path -Path (Split-Path $azurePolicySetPath -Parent) -ChildPath 'azurepolicyset.definitions.json'
        $azurePolicyPolicyDefinitionJson =  $azurePolicySet.properties.policyDefinitions | ConvertTo-Json -Depth 99 | Format-Json
        [System.IO.File]::WriteAllLines($azurePolicyPolicyDefinitionPath, $azurePolicyPolicyDefinitionJson)
    }
}