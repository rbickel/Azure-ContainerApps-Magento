## Azure Container Apps -> Magento2 Commerce (Bitnami image)
  This bicep template deploys a Magento2 Commerce in Azure Container Apps and Azure MySQL Flexi server. It is based on Bitnami Magento docker image and official Elasticsearch docker image.
  
![image](https://user-images.githubusercontent.com/11852796/193596181-75f90621-03a4-46cb-9285-4758e4f9226d.png)

## What does it deploy ?

[x] Azure Container Apps

[x] Azure MySQL Flexi server

[x] Elasticsearch in Container Apps

[x] Bitnami Magento2 in Container Apps

[x] Storage account for uploads/ backups persistence

[x] Log analytics workspace for container logs

## Why it is NOT production ready ?

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
