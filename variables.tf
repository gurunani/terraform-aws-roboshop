variable "project" {
  default = "Roboshop"
  type    = string
}

variable "environment" {
  default = "dev"
  type    = string
}

variable "zone_id" {
  default = "Z08007301TGLKBZ7OY820"
  type    = string
}

variable "zone_name" {
  default = "gurulabs.xyz"
  type    = string
}

variable "component" {
  description = "Name of the Roboshop component"
  type        = string
}

variable "rule_priority" {
  description = "Priority for the ALB listener rule"
  type        = number
}