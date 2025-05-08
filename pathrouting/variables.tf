variable "subscription_id" {
  description = "A prefix used for all resources in this example."
  type        = string
}

variable "prefix" {
  description = "A prefix used for all resources in this example."
  type        = string
}

variable "location" {
  description = "The Azure Region in which all resources will be created."
  type        = string
  default     = "Germany West Central"
}

variable "storage_account_name_1" {
  description = "The name of the first storage account"
  type        = string
  default     = "cptdagwstorage1" # Optional: Set a default value
}

variable "storage_account_name_2" {
  description = "The name of the second storage account"
  type        = string
  default     = "cptdagwstorage2" # Optional: Set a default value
}
