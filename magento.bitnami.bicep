param name string = 'magento'
param location string = 'northeurope'

@secure()
param magentoUsername string = 'user'
@secure()
param magentoPassword string = 'bitnami1'
@secure()
param mysqlUsername string = 'magento'
@secure()
param mysqlPassword string = 'Password123_'

var uniqueName = '${name}${uniqueString(resourceGroup().id, subscription().id)}'

// resource redis 'Microsoft.Cache/redis@2022-05-01' existing = {
//   name: 'rbklmagento'
//   scope: 'magento3'
// }

var redisPassword = 'tFcbC2WAqGjJqvgpj6UsYmYoZd212k3vMAzCaCUjAbA=' // redis.properties.accessKeys.primaryKey
var redisHost = 'rbklmagento.redis.cache.windows.net' //redis.properties.hostName

resource vnet 'Microsoft.Network/virtualNetworks@2022-01-01' = {
  name: '${name}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/8'
      ]
    }
    subnets: [
      {
        name: '${name}-subnet'
        properties: {
          addressPrefix: '10.1.0.0/23'
        }
      }
    ]
  }
}

resource mysql 'Microsoft.DBforMySQL/flexibleServers@2021-05-01-preview' = {
  name: uniqueName
  location: location
  sku: {
    name: 'Standard_B4ms'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: mysqlUsername
    administratorLoginPassword: mysqlPassword
    version: '5.7'
  }
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: '${name}-id'
  location: location
}

var contributorDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
@description('This is the built-in Contributor role. See https://docs.microsoft.com/azure/role-based-access-control/built-in-roles#contributor')
resource contributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  scope: subscription()
  name: contributorDefinitionId
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  scope: mysql
  name: guid(mysql.id, identity.id, contributorDefinitionId)
  properties: {
    roleDefinitionId: contributorRoleDefinition.id
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// This is required as so far I didn't find a way to use SSL with the bitnami image in Container Apps
resource disableMysqlSSL 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${name}-disable-mysql-ssl'
  location: location
  dependsOn: [ roleAssignment ]
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.37.0'
    retentionInterval: 'P1D'
    timeout: 'PT30M'
    scriptContent: 'az mysql flexible-server parameter set -g ${resourceGroup().name} --server ${mysql.name} --name require_secure_transport --value OFF'
  }
}

resource firewallRule 'Microsoft.DBforMySQL/flexibleServers/firewallRules@2021-12-01-preview' = {
  name: 'allow-all'
  parent: mysql
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

resource mysqlDatabase 'Microsoft.DBforMySQL/flexibleServers/databases@2021-12-01-preview' = {
  name: 'magento2'
  parent: mysql
  properties: {
    collation: 'utf8_general_ci'
    charset: 'utf8'
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: name
  location: location
}

resource managedEnvironment 'Microsoft.App/managedEnvironments@2022-03-01' = {
  location: location
  name: name
  properties: {
    vnetConfiguration: {
      internal: false
      infrastructureSubnetId: vnet.properties.subnets[0].id
      runtimeSubnetId: vnet.properties.subnets[0].id
    }
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: listKeys(logAnalyticsWorkspace.id, logAnalyticsWorkspace.apiVersion).primarySharedKey
      }
    }
  }
}

resource magentoStorage 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  location: location
  name: uniqueName
  kind: 'FileStorage'
  sku: {
    name: 'Premium_LRS'
  }
  properties: {
    accessTier: 'Premium'
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2021-09-01' = {
  name: 'default'
  parent: magentoStorage
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2021-04-01' = {
  name: '${magentoStorage.name}/default/magento'
  dependsOn: [ fileService ]
}

resource managedEnvironmentStorageUploads 'Microsoft.App/managedEnvironments/storages@2022-03-01' = {
  name: 'magento'
  parent: managedEnvironment
  dependsOn: [
    fileShare
  ]
  properties: {
    azureFile: {
      accessMode: 'ReadWrite'
      accountKey: listKeys(magentoStorage.id, magentoStorage.apiVersion).keys[0].value
      accountName: magentoStorage.name
      shareName: 'magento'
    }
  }
}

resource elasticApp 'Microsoft.App/containerApps@2022-03-01' = {
  location: location
  name: '${name}-elastic'
  properties: {
    configuration: {
      ingress: {
        external: false
        targetPort: 9200
      }
    }
    managedEnvironmentId: managedEnvironment.id
    template: {
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
      containers: [
        {
          name: 'elastic'
          image: 'docker.elastic.co/elasticsearch/elasticsearch:7.17.5'
          resources: {
            cpu: 2
            memory: '4Gi'
          }
          env: [
            {
              name: 'discovery.type'
              value: 'single-node'
            }
          ]
        }
      ]
    }
  }
}

//magento environment variables and secrets
var env = [
  {
    name: 'MAGENTO_DATABASE_NAME'
    value: mysqlDatabase.name
  }
  {
    name: 'MAGENTO_ELASTICSEARCH_HOST'
    value: elasticApp.properties.configuration.ingress.fqdn
  }
  {
    name: 'MAGENTO_HOST'
    value: '${name}.${managedEnvironment.properties.defaultDomain}'
  }
  {
    name: 'MAGENTO_DATABASE_HOST'
    value: mysql.properties.fullyQualifiedDomainName
  }
  {
    name: 'BITNAMI_DEBUG'
    value: 'true'
  }
  {
    name: 'MAGENTO_ELASTICSEARCH_USE_HTTPS'
    value: 'yes'
  }
  {
    name: 'MAGENTO_ELASTICSEARCH_PORT_NUMBER'
    value: '443'
  }
  {
    name: 'MAGENTO_ENABLE_HTTPS'
    value: 'yes'
  }
  {
    name: 'MAGENTO_ENABLE_ADMIN_HTTPS'
    value: 'yes'
  }
  {
    name: 'MAGENTO_VERIFY_DATABASE_SSL'
    value: 'no'
  }
  {
    name: 'MAGENTO_ENABLE_DATABASE_SSL'
    value: 'yes'
  }
  {
    name: 'ALLOW_EMPTY_PASSWORD'
    value: 'yes'
  }
  {
    name: 'MAGENTO_DATABASE_USER'
    secretRef: 'mysqluser'
  }
  {
    name: 'MAGENTO_DATABASE_PASSWORD'
    secretRef: 'mysqlpassword'
  }
  {
    name: 'MAGENTO_EXTRA_INSTALL_ARGS'
    secretRef: 'extraargs'
  }
]
var secrets = [
  {
    name: 'mysqluser'
    value: mysqlUsername
  }
  {
    name: 'mysqlpassword'
    value: mysqlPassword
  }
  {
    name: 'extraargs'
    value: '--page-cache=redis --page-cache-redis-db=1 --page-cache-redis-server=${redisHost} --page-cache-redis-password=${redisPassword} --cache-backend=redis --cache-backend-redis-server=${redisHost} --cache-backend-redis-password=${redisPassword} --cache-backend-redis-db=2 --session-save=redis --session-save-redis-password=${redisPassword} --session-save-redis-host=${redisHost}'
  }
]

resource redisApp 'Microsoft.App/containerApps@2022-03-01' = {
  location: location
  name: '${name}-redis'
  properties: {
    configuration: {
      ingress: {
        external: false
        targetPort: 6379
        transport: 'tcp'
      }
    }
    managedEnvironmentId: managedEnvironment.id
    template: {
      containers: [
        {
          name: 'redis'
          image: 'redis:5.0.3'
          resources: {
            cpu: 1
            memory: '2Gi'
          }
          env: [
            {
              name: 'ALLOW_EMPTY_PASSWORD'
              value: 'yes'
            }
            {
              name: 'REDIS_PASSWORD'
              value: redisPassword
            }
          ]
        }
      ]
    }
  }
}

resource magentoApp 'Microsoft.App/containerApps@2022-03-01' = {
  location: location
  dependsOn: [
    mysqlDatabase
    disableMysqlSSL
    firewallRule
    elasticApp
    redisApp
  ]
  name: name
  properties: {
    managedEnvironmentId: managedEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      secrets: secrets
      ingress: {
        external: true
        targetPort: 8080
        allowInsecure: true
      }
    }
    template: {
      scale: {
        minReplicas: 1
        maxReplicas: 5
        rules: [
          {
            name: 'http-rule'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
      volumes: [
        {
          name: 'magento'
          storageType: 'EmptyDir'
        }
        // {
        //   name: managedEnvironmentStorageUploads.name
        //   storageName: managedEnvironmentStorageUploads.name
        //   storageType: 'AzureFile'
        // }
        // {
        //   name: managedEnvironmentStorageBackups.name
        //   storageName: managedEnvironmentStorageBackups.name
        //   storageType: 'AzureFile'
        // }
      ]
      containers: [
        {
          name: 'magento'
          image: 'bitnami/magento:latest'
          args: [
            '/opt/bitnami/scripts/magento/run.sh'
          ]
          resources: {
            cpu: 2
            memory: '4Gi'
          }
          env: env
          probes: [
            {
              type: 'Startup' //Magento startup can take a while to complete
              initialDelaySeconds: 60
              periodSeconds: 10
              timeoutSeconds: 30
              failureThreshold: 10
              successThreshold: 1
              httpGet: {
                path: '/'
                port: 8080
                scheme: 'HTTP'
              }
            }
            {
              type: 'Liveness'
              periodSeconds: 5
              timeoutSeconds: 30
              failureThreshold: 3
              successThreshold: 1
              httpGet: {
                path: '/'
                port: 8080
                scheme: 'HTTP'
              }
            }
            {
              type: 'Readiness'
              periodSeconds: 5
              timeoutSeconds: 30
              failureThreshold: 3
              successThreshold: 1
              httpGet: {
                path: '/'
                port: 8080
                scheme: 'HTTP'
              }
            }
          ]
          volumeMounts: [
            {
              volumeName: 'magento'
              mountPath: '/bitnami/magento'
            }
          ]
        }
      ]
    }
  }
}

output magento_url string = 'https://${magentoApp.properties.configuration.ingress.fqdn}'
output redis_internal_fqdn string = redisApp.properties.configuration.ingress.fqdn
