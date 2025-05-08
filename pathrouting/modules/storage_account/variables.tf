variable "name" {
  description = "The name of the storage account"
  type        = string
}

variable "location" {
  description = "The location of the storage account"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
}

variable "access_tier" {
  description = "The access tier of the storage account"
  type        = string
  default     = "Hot"
}

variable "account_kind" {
  description = "The kind of storage account"
  type        = string
  default     = "StorageV2"
}

variable "account_replication_type" {
  description = "The replication type of the storage account"
  type        = string
  default     = "LRS"
}

variable "account_tier" {
  description = "The tier of the storage account"
  type        = string
  default     = "Standard"
}

variable "change_feed_enabled" {
  description = "Whether change feed is enabled"
  type        = bool
  default     = false
}

variable "last_access_time_enabled" {
  description = "Whether last access time tracking is enabled"
  type        = bool
  default     = false
}

variable "versioning_enabled" {
  description = "Whether versioning is enabled"
  type        = bool
  default     = false
}

variable "default_action" {
  description = "Default action for network rules"
  type        = string
  default     = "Allow"
}

variable "ip_rules" {
  description = "IP rules for network access"
  type        = list(string)
  default     = []
}

variable "virtual_network_subnet_ids" {
  description = "List of subnet IDs for virtual network rules"
  type        = list(string)
}

variable "container_name" {
  description = "The name of the storage container"
  type        = string
}

variable "container_access_type" {
  description = "The access type of the storage container"
  type        = string
  default     = "blob"
}
