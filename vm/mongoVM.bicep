@description('Location for all resources.')
param location string = 'eastus'
param customerName string
param env string

// VNet Configuration Params
param subnetId string 

// User-Assigned Managed Id Configuration
param userAssignedClientId string
param userAssignedResId string


// Azure Key Vault Vars
param mgtAkv string

// Mongo Configuration Vars
param mongoSuperUserName string
param mongoSuperUserSecret string 
var mongoNFormatScriptContent = loadTextContent('../formatNmongodb.ps1', 'utf-8')


// VM Configuration Vars
@description('Name of the virtual machine.')
param vmName string


//  This is the public IP from the workstation that is executing the script
param scriptPip string


@description('Name for the Public IP used to access the Virtual Machine.')
var publicIpName = 'pip-${vmName}-${env}'

@description('Allocation method for the Public IP used to access the Virtual Machine.')
@allowed([
  'Dynamic'
  'Static'
])
param publicIPAllocationMethod string = 'Dynamic'

@description('SKU for the Public IP used to access the Virtual Machine.')
@allowed([
  'Basic'
  'Standard'
])
param publicIpSku string = 'Basic'

@description('Unique DNS Name for the Public IP used to access the Virtual Machine.')
param dnsLabelPrefix string = toLower('${vmName}-${customerName}')

@description('The Windows version for the VM. This will pick a fully patched Gen2 image of this given Windows version.')
@allowed([
 '2019-datacenter-gensecond'
 '2019-datacenter-core-gensecond'
 '2019-datacenter-core-smalldisk-gensecond'
 '2019-datacenter-core-with-containers-gensecond'
 '2019-datacenter-core-with-containers-smalldisk-g2'
 '2019-datacenter-smalldisk-gensecond'
 '2019-datacenter-with-containers-gensecond'
 '2019-datacenter-with-containers-smalldisk-g2'
 '2016-datacenter-gensecond'
])
param OSVersion string = '2019-datacenter-gensecond'

@description('Size of the virtual machine.')
param vmSize string = 'Standard_D2s_v3'

@description('Username for the Virtual Machine.')
param adminUsername string

@description('Password for the Virtual Machine.')
@minLength(12)
@secure()
param adminPassword string





var storageAccountName = 'diags4vms${customerName}'
var nicName = '${vmName}VMNic'
var networkSecurityGroupName = 'NSG-${vmName}'

resource stg 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'Storage'
}

resource pip 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: publicIpName
  location: location
  sku: {
    name: publicIpSku
  }
  properties: {
    publicIPAllocationMethod: publicIPAllocationMethod
    dnsSettings: {
      domainNameLabel: dnsLabelPrefix
    }
  }
}

resource securityGroup 'Microsoft.Network/networkSecurityGroups@2021-02-01' = {
  name: networkSecurityGroupName
  location: location
  properties: {
    securityRules: [
      {
        name: 'RDP-In-From-Wkstn-3389'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '3389'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: scriptPip
          destinationAddressPrefix: '*'
        
        }
      }
      {
        name: 'allow-mongo-27017'
        properties: {
          priority: 1001
          direction: 'Inbound'
          protocol: 'Tcp'
          access: 'Allow'
          destinationPortRange: '27017'
          destinationAddressPrefix: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: scriptPip
        }
      }
    ]
  }
}

// resource vn 'Microsoft.Network/virtualNetworks@2021-02-01' = {
//   name: virtualNetworkName
//   location: location
//   properties: {
//     addressSpace: {
//       addressPrefixes: [
//         addressPrefix
//       ]
//     }
//     subnets: [
//       {
//         name: subnetName
//         properties: {
//           addressPrefix: subnetPrefix
//           networkSecurityGroup: {
//             id: securityGroup.id
//           }
//         }
//       }
//     ]
//   }
// }

resource nic 'Microsoft.Network/networkInterfaces@2021-02-01' = {
  name: nicName
  location: location
  properties: {
    networkSecurityGroup:{
      id: securityGroup.id
    }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: pip.id
          }
          subnet: {
            id: subnetId
          }

        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2021-11-01' = {
  name: vmName
  location: location
  identity:{
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${userAssignedResId}': {}
    }
  }
  properties: {
    
    hardwareProfile: {
      vmSize: vmSize
    }
    
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: OSVersion
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        name: '${vmName}_OSDisk'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
      dataDisks: [
        {
          diskSizeGB: 512
          lun: 0
          createOption: 'Empty'
          name: '${vmName}_datadisk'
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }

      ]
    }
    
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: stg.properties.primaryEndpoints.blob
      }
    }
    
  }

}

resource windowsAgent 'Microsoft.Compute/virtualMachines/extensions@2021-11-01' = {
  parent: vm
  name: 'AzureMonitorWindowsAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    
  }
}

// resource runCmd4Mongo 'Microsoft.Compute/virtualMachines/runCommands@2021-11-01' = {
//   parent: vm
//   name: 'MongoNFormatPoSH'
//   location: location
//   properties: {
//     source: {
//       script: mongoNFormatScriptContent
//     }
//     parameters: [
//       {
//         name: 'akvName'
//         value: mgtAkv
//       }
//       {
//         name: 'superUserName'
//         value: mongoSuperUserName
//       }
//       {
//         name: 'secretName'
//         value: mongoSuperUserSecret
//       }
//       {
//         name: 'akvName'
//         value: userAssignedClientId
//       }
//     ]
//   }
// }

output hostname string = pip.properties.dnsSettings.fqdn
