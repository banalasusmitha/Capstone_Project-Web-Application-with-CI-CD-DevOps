variable "name" {
  description = "Name prefix applied to every resource in this module."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name (used for the kubernetes.io/cluster subnet tags)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets across."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "EKS requires subnets in at least 2 AZs; 4 is the practical maximum here."
  }
}

variable "enable_nat_gateway" {
  description = "Create NAT Gateway(s) so private subnets reach the internet. Set false to run nodes in public subnets and save ~$32/month."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use one shared NAT Gateway instead of one per AZ (cost optimisation)."
  type        = bool
  default     = true
}

variable "admin_cidrs" {
  description = "CIDRs allowed to SSH into Jenkins and reach the Jenkins UI."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
