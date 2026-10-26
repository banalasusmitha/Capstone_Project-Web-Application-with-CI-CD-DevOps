variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version for the control plane."
  type        = string
  default     = "1.36"
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (control plane ENIs + internet-facing load balancers)."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs."
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "Subnets the worker nodes are launched into."
  type        = list(string)
}

variable "additional_security_group_ids" {
  description = "Extra security groups attached to the control plane."
  type        = list(string)
  default     = []
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API endpoint publicly (needed for kubectl from your laptop)."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Narrow this in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enabled_cluster_log_types" {
  description = "Control plane log types to ship to CloudWatch. Use [] to disable and save cost."
  type        = list(string)
  default     = ["api", "authenticator"]
}

variable "log_retention_days" {
  description = "CloudWatch retention for control plane logs."
  type        = number
  default     = 7
}

variable "capacity_type" {
  description = "ON_DEMAND or SPOT. SPOT is 60-70% cheaper and fine for this capstone."
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "instance_types" {
  description = "Instance types for the node group. Listing several improves Spot availability."
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "ami_type" {
  description = "EKS-optimised AMI family for the node group."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_disk_size" {
  description = "EBS root volume size per node, in GiB."
  type        = number
  default     = 20
}

variable "desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}

variable "enable_metrics_server" {
  description = "Install the metrics-server add-on. Required by the Horizontal Pod Autoscaler and by `kubectl top`."
  type        = bool
  default     = true
}

variable "cluster_admin_principals" {
  description = "Map of static label => IAM principal ARN granted cluster-admin."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
