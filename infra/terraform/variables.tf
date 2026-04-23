variable "subscription_id" {
  description = "Azure Subscription ID where resources will be provisioned."
  type        = string
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
}

variable "environment" {
  description = "Environment name (for tags and naming)."
  type        = string
}

variable "project_name" {
  description = "Project/application name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name."
  type        = string
}

variable "acr_name" {
  description = "Globally unique ACR name (5-50 alphanumeric chars)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.acr_name))
    error_message = "ACR name must be 5-50 alphanumeric characters."
  }
}

variable "aks_name" {
  description = "AKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version."
  type        = string
}

variable "node_count" {
  description = "Initial AKS system node count."
  type        = number
}

variable "node_vm_size" {
  description = "AKS node VM size."
  type        = string
}
