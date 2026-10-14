variable "name" {
  description = "Name prefix for every resource in this module."
  type        = string
}

variable "subnet_id" {
  description = "Public subnet to launch the agent in, so it is reachable over SSH for Ansible."
  type        = string
}

variable "security_group_id" {
  description = "Security group for the agent. The Jenkins SG is reused because the EKS control plane already trusts it on port 443, which kubectl deploys need."
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile giving the agent ECR, EKS and state-bucket access without stored keys."
  type        = string
}

variable "public_key" {
  description = "Contents of the SSH public key (the .pub file). Safe to commit - it is not a secret."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256) ", var.public_key))
    error_message = "public_key must be the contents of a .pub file, starting with ssh-ed25519, ssh-rsa or ecdsa-sha2-nistp256. Did you paste the private key by mistake?"
  }
}

variable "instance_type" {
  description = "Instance type. Must be free-tier eligible while the account is on the AWS Free Plan."
  type        = string
  default     = "c7i-flex.large"
}

variable "root_volume_size" {
  description = "Root volume size in GiB. Build agents accumulate Docker images."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
