moved {
  from = azapi_resource.apim
  to   = azapi_resource.apim[0]
}

moved {
  from = azurerm_role_assignment.apim_foundry_user
  to   = azurerm_role_assignment.apim_foundry_user[0]
}

moved {
  from = time_sleep.wait_for_apim_foundry_rbac
  to   = time_sleep.wait_for_apim_foundry_rbac[0]
}

moved {
  from = azurerm_api_management_tag.ai_model
  to   = azurerm_api_management_tag.ai_model[0]
}

moved {
  from = azurerm_private_endpoint.apim
  to   = azurerm_private_endpoint.apim[0]
}
