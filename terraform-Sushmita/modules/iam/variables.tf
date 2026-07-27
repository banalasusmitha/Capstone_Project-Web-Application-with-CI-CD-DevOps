variable "name" {
  description = "Name prefix for IAM resources."
  type        = string
}

variable "region" {
  description = "AWS region (used to build the DynamoDB lock table ARN)."
  type        = string
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs Jenkins may push to. Empty list falls back to \"*\"."
  type        = list(string)
  default     = []
}

variable "tf_state_bucket" {
  description = "S3 bucket holding the Terraform remote state."
  type        = string
}

variable "tf_lock_table_name" {
  description = "DynamoDB lock table name. Leave empty when using S3 native locking."
  type        = string
  default     = ""
}

variable "allow_jenkins_to_run_terraform" {
  description = "Attach PowerUserAccess so the Jenkins infrastructure job can run terraform apply."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to IAM resources."
  type        = map(string)
  default     = {}
}
