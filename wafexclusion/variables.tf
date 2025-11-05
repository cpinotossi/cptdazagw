variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
  default     = "4896a771-b1ab-4411-bd94-3c8467f1991e"
}

variable "admin_username" {
  description = "Admin username for VMs"
  type        = string
  default     = "azureuser"
}

variable "admin_password" {
  description = "Admin password for VMs"
  type        = string
  default     = "P@ssw0rd123!"
  sensitive   = true
}