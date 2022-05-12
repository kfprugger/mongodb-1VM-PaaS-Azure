# Connect to Azure w/ Azure User Managed Identity Acct ID
$azUserAssignedId = "a3ff0c85-6f0c-4274-bc3b-3757667fa2dc"
$AzureContext = (Connect-AzAccount -Identity -AccountId $azUserAssignedId).context

# Azure Key Vault Variables containing super user credential
$akvName = "akv-pai-mgt"
$secretName = "mongodb-superadmin"
$superUserName = "joeyadmin"
## get the password
$sUserPwd = (Get-AzKeyVaultSecret -VaultName $akvName -Name $secretName -AsPlainText)

# Mongo Download Links (change for future Releases)
$shellUrl = "https://downloads.mongodb.com/compass/mongosh-1.3.1-x64.msi"
$dbUrl = "https://fastdl.mongodb.org/windows/mongodb-windows-x86_64-5.0.8-signed.msi"
$mongoBinDir = "M:\MongoDB\Server\5.0\bin" # you might need to change if releases change bin directory structures

## Super user admin name
$adminUserName="paiadmin" 





function Set-ServiceRecovery{
    [alias(‘Set-Recovery’)]
    param
    (
    [string] [Parameter(Mandatory=$true)] $ServiceName,
    [string] [Parameter(Mandatory=$true)] $Server,
    [string] $action1 = “restart”,
    [int] $time1 = 30000, # in miliseconds
    [string] $action2 = “restart”,
    [int] $time2 = 30000, # in miliseconds
    [string] $actionLast = “restart”,
    [int] $timeLast = 30000, # in miliseconds
    [int] $resetCounter = 4000 # in seconds
    )
     $serverPath = “\\” + $server
     $services = Get-CimInstance -ClassName ‘Win32_Service’ -ComputerName $Server| Where-Object {$_.Name -contains $ServiceName}
     $action = $action1+“/”+$time1+“/”+$action2+“/”+$time2+“/”+$actionLast+“/”+$timeLast
    foreach ($service in $services){
        # https://technet.microsoft.com/en-us/library/cc742019.aspx
        sc.exe $serverPath failure $($service.Name) actions= $action reset= $resetCounter
        echo $serverPath
        echo "Modifying: $service.Name"
        echo $output
    }
}


if (!(get-psdrive -Name "M" -ErrorAction SilentlyContinue)){
    if (Get-Disk | Where PartitionStyle -eq 'raw'){
    $partMDrive = Get-Disk | Where PartitionStyle -eq 'raw' |
    Initialize-Disk -PartitionStyle GPT -PassThru |
    New-Partition  -UseMaximumSize -DriveLetter M -ErrorVariable $partError |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel "DataDisk"  -Confirm:$false -ErrorVariable $partError 

    Write-Host "Initialization of M:\ Filesystem on the data disk is: " $partError $partMDrive.OperationalStatus} else {
        write-host "No data disk present. Breaking out of script"
        $error[0] =  "No data disk present. Breaking out of script"
        break 
        
    }

} else {
    Write-Host "M:\ filesystem already initialized"
}

Start-Sleep 5

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force


if (!(Get-Module Az.KeyVault)){
    if (!(Get-PackageProvider -Name NuGet)) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-PackageProvider -Name NuGet -Force 
    }
    Install-Module Az.Resources -Force -Confirm:$false
    Install-Module Az.KeyVault -Force -Confirm:$false
    Import-Module Az.Resources
    Import-Module Az.KeyVault
} else {
    Import-Module Az.Resources
    Import-Module Az.KeyVault 
}

# Install MongoDB Server

$dlLocation = "M:\Downloads"
$msiDb = ($dburl -split "/")[4]
if (!(test-path $dlLocation)) {mkdir $dlLocation}

$outFileLocation = "$dlLocation\$msiDb"
if (!(test-path $outfilelocation)){Invoke-WebRequest -Uri $dbUrl -OutFile $outFileLocation} else {
    echo "$outFileLocation  is present"
}
if (!(Get-Service MongoDB -ErrorAction SilentlyContinue )){
    Get-Date
    Start-Process -WorkingDirectory $dlLocation -FilePath msiexec -ArgumentList "/l*v mdbinstall.log  /qb /i $msidb INSTALLLOCATION=""M:\MongoDB\Server\5.0\"" ADDLOCAL=""ALL"" " -Wait:$true
    write-host " now done with server install"
    Get-Date
} else {
    write-host "mongo is already installed"
}



# Install Mongo DB Shell


$msiShellPath = ($shellUrl -split "/")[4]
$outFileLocation = "$dlLocation\$msiShellPath"

if (!(test-path $outfilelocation)){Invoke-WebRequest -Uri $shellUrl -OutFile $outFileLocation} else {
    echo "$outFileLocation  is present"
}

if (!(test-path monogosh -ErrorAction SilentlyContinue )){
    start-process msiexec.exe `
    -argumentlist "/l*v mshinstall.log  /qn /i $msiShellPath" `
    -WorkingDirectory $dlLocation -Wait
} else {
    write-host "mongo shell is already installed"
}

# Install Mongo Compass
## Because we selected "ADDLOCAL=ALL" in mongoDB installation, you can just invoke the included script in the .\bin dir
# powershell $mongoBinDir\installcompass.ps1

# Set aliases for current shell

Set-Alias mongosh "C:\Users\$adminUserName\AppData\Local\Programs\mongosh\mongosh.exe"
Set-Alias mongo "$mongoBinDir\mongo.exe"



# Allow Secure User External Access with Superuser name and pwd
## Set Windows FW to allow; Control access using Azure's NSGs
New-NetFirewallRule -DisplayName "Mongodb-inbound" -Direction Inbound -LocalPort 27017 -Protocol TCP -Action Allow

# Begin update for SuperUser
## FIRST: Get the super user script with placeholders
Invoke-WebRequest -Uri https://raw.githubusercontent.com/kfprugger/mongodb-1VM-PaaS-Azure/main/addSuperUserLogin.js -OutFile "$dlLocation\addSuperUserLogin.js"

## SECOND: Replace the placeholders with your variables
(Get-Content "$dlLocation\addSuperUserLogin.js").replace('[PWD_REPLACE_ME]', $sUserPwd) | Set-Content "$dlLocation\addSuperUserLogin.js"

(Get-Content "$dlLocation\addSuperUserLogin.js").replace('[ADMIN_REPLACE_ME]', $superUserName) | Set-Content "$dlLocation\addSuperUserLogin.js"

## LAST: Execute the file to add your superuser into the admin DB
mongosh -f "$dlLocation\addSuperUserLogin.js"


# Set your server config file to allow connections
(Get-Content -Path "$mongoBinDir\mongod.cfg").Replace('127.0.0.1', '0.0.0.0') | Set-Content "$mongoBinDir\mongod.cfg"
(Get-Content -Path "$mongoBinDir\mongod.cfg").Replace('#security:', "security: `n authorization: ""enabled""") | Set-Content "$mongoBinDir\mongod.cfg"

# Restart Mongo and set to recover itself in case of stoppage
restart-service MongoDB
Set-ServiceRecovery -ServiceName "MongoDB” -Server $env:computername