## Azure Container Apps -> Magento Commerce (Bitnami image)
  This bicep template deploys a Magento Commerce in Azure Container Apps and Azure MySQL Flexi server. It is based on Bitnami Magento docker image and official Elasticsearch docker image.
  
![image](https://user-images.githubusercontent.com/11852796/184132916-1aae7d6b-c924-4e85-ac97-3cccbacc516f.png)

## What does it deploy ?

[x] Azure Container Apps

[x] Azure MySQL Flexi server

[x] Elasticsearch in Container Apps

[x] Bitnami Magento in Container Apps

[x] Storage account for uploads/ backups persistence

[x] Log analytics workspace for container logs

## Why it is NOT production ready ?

- Does not support Bring-Your-Own-Vnet
- MySql Server firewall is fully open
- MySql SSL is not enforced
- Storage account firewall is fully open
- Passwords are weak and have known defaults (`bitnami1`, `Password123_`)
- When scaling out, the maintenance page is activated until the new replica goes live
- High-Availability, Backups, etc...
- Not thoroughly tested

## How to use it ?

```bash
az group create --name my-group --location northeurope
az deployment group create --resource-group my-group --template-file ./magento.bitnami.bicep
```
