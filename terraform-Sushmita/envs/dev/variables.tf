###############################################################################
# GENERAL
###############################################################################

variable "aws_region" {
  description = "AWS region for every resource."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project slug used in resource names and tags."
  type        = string
  default     = "shopnow"
}

variable "environment" {
  description = "Environment name (dev / stage / prod)."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owner tag - useful when four people share one AWS account."
  type        = string
  default     = "susmitha"
}

###############################################################################
# NETWORKING
###############################################################################

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones."
  type        = number
  default     = 2
}

variable "enable_nat_gateway" {
  description = "Create a NAT Gateway. false = nodes run in public subnets (~$32/month cheaper, less secure)."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Share one NAT Gateway across AZs."
  type        = bool
  default     = true
}

variable "admin_cidrs" {
  description = "CIDRs allowed to reach SSH and the Jenkins UI. Replace with <your-ip>/32."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

###############################################################################
# ECR
###############################################################################

variable "create_ecr_repositories" {
  description = "Set false if the repositories already exist and you have not imported them."
  type        = bool
  default     = true
}

variable "app_user_name" {
  description = "The ShopNow USER_NAME identifier. It is the Docker build arg, the ingress path prefix (/<name> and /<name>-admin) and the ECR namespace prefix. Must be the same value in the Dockerfiles, the manifests and here."
  type        = string
  default     = "avinash"
}

variable "ecr_namespace" {
  description = "Override the repository prefix. Leave null to use \"<app_user_name>-shopnow\"."
  type        = string
  default     = null
}

variable "services" {
  description = "ShopNow services that each get their own repository."
  type        = list(string)
  default     = ["frontend", "admin", "backend"]
}

variable "ecr_max_image_count" {
  description = "Images retained per repository."
  type        = number
  default     = 10
}

variable "ecr_untagged_expire_days" {
  description = "Days before untagged images are expired."
  type        = number
  default     = 3
}

###############################################################################
# EKS
###############################################################################

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "shopnow-eks-dev"
}

variable "kubernetes_version" {
  description = "Kubernetes version. Check `aws eks describe-cluster-versions` if apply rejects it."
  type        = string
  default     = "1.36"
}

variable "cluster_public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enabled_cluster_log_types" {
  description = "Control plane logs sent to CloudWatch. [] disables logging entirely."
  type        = list(string)
  default     = ["api", "authenticator"]
}

variable "enable_metrics_server" {
  description = "Install the metrics-server add-on (required by the HPA)."
  type        = bool
  default     = true
}

variable "capacity_type" {
  description = "SPOT or ON_DEMAND worker nodes."
  type        = string
  default     = "SPOT"
}

variable "instance_types" {
  description = "Worker node instance types."
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "desired_size" {
  description = "Desired worker node count."
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum worker node count."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum worker node count."
  type        = number
  default     = 4
}

variable "team_principal_arns" {
  description = "Teammate IAM user/role ARNs that need kubectl access to the cluster."
  type        = list(string)
  default     = []
}

###############################################################################
# STATE / JENKINS
###############################################################################

variable "tf_state_bucket" {
  description = "S3 bucket holding Terraform state (must match backend.hcl)."
  type        = string
}

variable "tf_lock_table_name" {
  description = "DynamoDB lock table name. Empty when using S3 native locking."
  type        = string
  default     = ""
}

variable "allow_jenkins_to_run_terraform" {
  description = "Attach PowerUserAccess to the Jenkins role so it can run terraform apply in Sprint 2."
  type        = bool
  default     = false
}

###############################################################################
# CI AGENT  (Sprint 3)
###############################################################################

variable "create_ci_agent" {
  description = "Create the CI agent EC2 that Ansible configures and Jenkins builds on."
  type        = bool
  default     = false
}

variable "ci_agent_public_key" {
  description = "Contents of the SSH public key (.pub) for the CI agent. Not a secret - safe to commit."
  type        = string
  default     = ""
}

variable "ci_agent_instance_type" {
  description = "Instance type for the CI agent. Must be free-tier eligible on the AWS Free Plan."
  type        = string
  default     = "c7i-flex.large"
}

variable "jenkins_server_role_name" {
  description = "IAM role name of the Jenkins server created by ../../jenkins/. Gets kubectl admin automatically once that stack exists."
  type        = string
  default     = "shopnow-jenkins-server-role"
}
