variable "aws_region" {
  description = "Region for the state bucket. Must match the backend region."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project slug used in resource names."
  type        = string
  default     = "shopnow"
}

variable "owner" {
  description = "Who owns these resources (shows up in tags and the AWS bill)."
  type        = string
  default     = "susmitha"
}

variable "create_dynamodb_lock_table" {
  description = "Create a DynamoDB lock table for Terraform < 1.10 compatibility."
  type        = bool
  default     = true
}
