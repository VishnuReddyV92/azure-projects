variable "project_name"         { default = "myapp" }
variable "location"             { default = "centralindia" }
variable "environment"          { default = "prod" }
variable "acr_sku"              { default = "Basic" }
variable "app_service_plan_sku" { default = "S1" }
variable "unique_suffix" {
  default = "vvr01"   # change to something unique to you, keep it short, lowercase, alphanumeric only
}