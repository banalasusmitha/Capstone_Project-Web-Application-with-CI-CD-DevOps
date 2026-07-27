variable "repository_names" {
  description = "Full ECR repository names, e.g. [\"avinash-shopnow/frontend\"]."
  type        = list(string)
}

variable "max_image_count" {
  description = "How many images to retain per repository before expiring the oldest."
  type        = number
  default     = 10
}

variable "untagged_expire_days" {
  description = "Delete untagged images older than this many days."
  type        = number
  default     = 3
}

variable "force_delete" {
  description = "Allow terraform destroy to delete repositories that still contain images."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to all repositories."
  type        = map(string)
  default     = {}
}
