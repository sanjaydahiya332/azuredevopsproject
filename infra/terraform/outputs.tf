output "resource_group_name" {
  description = "Resource group name."
  value       = azurerm_resource_group.rg.name
}

output "acr_name" {
  description = "Azure Container Registry name."
  value       = azurerm_container_registry.acr.name
}

output "acr_login_server" {
  description = "ACR login server used for docker push/pull."
  value       = azurerm_container_registry.acr.login_server
}

output "aks_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.aks.name
}
