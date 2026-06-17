[CmdletBinding()]
Param (

    [Parameter(Mandatory = $False)]
    [switch]$Manual
)

$ErrorActionPreference = "Stop"

Write-Verbose "`tInitializing variables..."

# Load correct variables according to the targeted environnement
. $PSScriptRoot/variables.local.ps1
Write-Verbose "Variables from local have been loaded..."

Disable-AzContextAutosave

Login-Azure -Manual:$Manual

# Get these values directly from  Azure resources
$dataInputFilePath = (Join-Path -Path $PSScriptRoot -ChildPath "./data/articles.csv")

$items = Import-Csv -Path $dataInputFilePath -Encoding utf8

#region SQL data import
$serverName =  $ENV_SQL_SERVER_NAME
$databaseName = $ENV_SQL_DATABASE_NAME
$tableName =  $ENV_SQL_DATA_TABLE_NAME
$tableSchema = $ENV_SQL_DATA_TABLE_SCHEMA

$token = az account get-access-token --resource "https://database.windows.net" | ConvertFrom-Json | Select-Object -ExpandProperty accessToken # Doesn't work with PowerShell

# Chunck items to avoid timeouts
$chunk_size = 1000
$counter = [pscustomobject] @{ Value = 0 }
$chunks = $items | Group-Object -Property { [math]::Floor($counter.Value++ / $chunk_size) }

Invoke-Sqlcmd -ServerInstance $serverName -Database $databaseName -Query "TRUNCATE TABLE $tableSchema.$tableName" -AccessToken $token

$chunks | ForEach-Object {
  Write-SqlTableData -InputData $_.Group -ServerInstance $serverName -DatabaseName $databaseName -SchemaName $tableSchema -TableName $tableName -Force -AccessToken $token
}

#endregion
