
param(
    # Resource Group to Deploy the resources
    [Parameter(Mandatory)]
    [string]
    $resourceGroupName,

    [Parameter(Mandatory)]
    [string]
    $env,

    [Parameter(Mandatory)]
    [string]
    $location,

    [Parameter(Mandatory)]
    [string]
    $customerName,

    [Parameter()]
    [string]
    $mgtRg,

    [Parameter()]
    [string]
    $mgtAkv,

    # Name of the User-Assigned Managed Identity
    [Parameter()]
    [string]
    $userAssignedMgdName,
    
    [Parameter(Mandatory)]
    [string]
    $adminGrp,

    [Parameter(Mandatory)]
    [string]
    $vmAdminName,

    [Parameter(Mandatory)]
    [string]
    $mongoAdminName
)

# $rg = "rg-pai-dev"
# $customerName = "pai"
# $env = "prd"




# $mgtRg = "rg-pai-mgt"
# $mgtAkv = "akv-pai-mgt"

if (!(Get-AzUserAssignedIdentity -Name $userAssignedMgdName -ResourceGroupName $mgtRg)){
    $uaiRg = (Get-AzUserAssignedIdentity | ? Name -eq $userAssignedMgdName).ResourceGroupName[0]
} else {
    $uaiRg = $mgtRg
}

$userAssignedResId = (Get-AzUserAssignedIdentity -Name $userAssignedMgdName -ResourceGroupName $uaiRg).Id
$userAssignedClientId = (Get-AzUserAssignedIdentity -Name $userAssignedMgdName -ResourceGroupName $uaiRg).ClientId

# VM + VM Admin info
$vmName = "mongo$customerName$env"
$adminPassword = (Get-AzKeyVaultSecret -VaultName $mgtAkv -SecretName $vmAdminName).SecretValue

# Mongo Info
$mongoSuperUserName = $mongoAdminName
$mongoSuperUserSecret = "mongodb-superadmin"

$scriptPip = (Invoke-WebRequest ifconfig.me/ip).Content.Trim()
$subnetId = (Get-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Name "vnt-pai-sfc-dev" | Get-AzVirtualNetworkSubnetConfig | ? Name -eq "snt-sfc-clients-dev").Id

$mongoDeploy = New-AzResourceGroupDeployment -Name "Mongo-VM-Deploy-$(Get-Date -format "MM-dd-yyyy_HH-mm")" `
    -ResourceGroupName $resourceGroupName `
    -Mode Incremental `
    -TemplateFile .\vm\mongoVM.bicep `
    -location $location `
    -customerName $customerName `
    -env $env `
    -subnetId $subnetId `
    -userAssignedClientId $userAssignedClientId `
    -userAssignedResId $userAssignedResId `
    -mgtAkv $mgtAkv `
    -mongoSuperUserName $mongoSuperUserName `
    -mongoSuperUserSecret $mongoSuperUserSecret `
    -vmName $vmName `
    -scriptPip $scriptPip `
    -adminUsername $vmAdminName `
    -adminPassword $adminPassword

# Parameters to pass to the Run Command after the VM is created
$params = @{
    "akvName" = "$mgtAkv";
    "superUserName" = "$mongoAdminName";
    "userAssignedClientId" = "$userAssignedClientId"
    }

# $params = @{
#     "akvName" = "akv-pai-mgt";
#     "superUserName" = "joeymongoadmin";
#     "secretName" = "mongodb-superadmin";
#     "userAssignedClientId" = "$userAssignedClientId"
#     }

# Get VM status from Azure by keying in on Microsoft Monitoring Agent (MMA)


# if ($mmaExt.Statuses | ? Code -EQ "ProvisioningState/succeeded" ) {
#     Write-Host "Running Mongo Setup on New VM"
#     $remoteSetupCmd = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroupName -Name $vmName -CommandId 'RunPowerShellScript' `
#     -ScriptPath "formatNmongodb.ps1" -Parameter $params 
#     Write-Host "Script ran with status code: "  $remoteSetupCmd.Error.Code
# } else {
#     Write-Host "VM is not ready. Cannot run Mongo configuration"
# }



if (((((Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -status).Extensions | ? Name -eq AzureMonitorWindowsAgent).Statuses).Code -ne "ProvisioningState/succeeded")) { 
    do {
        Write-Host "VM is not ready. Cannot run Mongo configuration"
        sleep 10
    } while (
        (((Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -status).Extensions | ? Name -eq AzureMonitorWindowsAgent).Statuses).Code -ne "ProvisioningState/succeeded") 
} else {
    Write-Host "Running Mongo Setup on New VM"
    $params
    # $setTraceCmd = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroupName -Name $vmName -CommandId 'RunPowerShellScript' -ScriptPath "Set-PSDebug -Trace 1"
    $remoteSetupCmd = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroupName -Name $vmName -CommandId 'RunPowerShellScript' `
    -ScriptPath ".\formatNmongodb.ps1" -Parameter $params -Verbose    
    $remoteSetupCmd.Value[0]
    Write-Host "Script ran with status code: "  
}
