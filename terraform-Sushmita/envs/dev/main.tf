###############################################################################
# DEV ENVIRONMENT - wires the modules together
###############################################################################

locals {
  name = "${var.project}-${var.environment}"

  tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
  }

  # The ShopNow project convention is <username>-shopnow/<service>, and the
  # same username is baked into the images as the USER_NAME build arg and
  # used as the ingress path. Keep app_user_name identical everywhere.
  ecr_namespace        = coalesce(var.ecr_namespace, "${var.app_user_name}-shopnow")
  ecr_repository_names = [for svc in var.services : "${local.ecr_namespace}/${svc}"]

  # With no NAT Gateway, private subnets have no route to the internet, so
  # nodes must live in public subnets or they can never join the cluster.
  node_subnet_ids = var.enable_nat_gateway ? module.vpc.private_subnet_ids : module.vpc.public_subnet_ids
}

###############################################################################
# NETWORKING
###############################################################################

module "vpc" {
  source = "../../modules/vpc"

  name         = local.name
  cluster_name = var.cluster_name
  vpc_cidr     = var.vpc_cidr
  az_count     = var.az_count

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway
  admin_cidrs        = var.admin_cidrs

  tags = local.tags
}

###############################################################################
# CONTAINER REGISTRY
###############################################################################

module "ecr" {
  source = "../../modules/ecr"
  count  = var.create_ecr_repositories ? 1 : 0

  repository_names     = local.ecr_repository_names
  max_image_count      = var.ecr_max_image_count
  untagged_expire_days = var.ecr_untagged_expire_days
  force_delete         = true

  tags = local.tags
}

###############################################################################
# IAM FOR JENKINS
###############################################################################

module "iam" {
  source = "../../modules/iam"

  name   = local.name
  region = var.aws_region

  ecr_repository_arns = var.create_ecr_repositories ? values(module.ecr[0].repository_arns) : []

  tf_state_bucket                = var.tf_state_bucket
  tf_lock_table_name             = var.tf_lock_table_name
  allow_jenkins_to_run_terraform = var.allow_jenkins_to_run_terraform

  tags = local.tags
}

###############################################################################
# EKS CLUSTER
###############################################################################

module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version

  public_subnet_ids             = module.vpc.public_subnet_ids
  private_subnet_ids            = module.vpc.private_subnet_ids
  node_subnet_ids               = local.node_subnet_ids
  additional_security_group_ids = [module.vpc.eks_control_plane_extra_sg_id]

  public_access_cidrs       = var.cluster_public_access_cidrs
  enabled_cluster_log_types = var.enabled_cluster_log_types

  # metrics-server backs the HPA that the ShopNow deployments rely on.
  enable_metrics_server = var.enable_metrics_server

  capacity_type  = var.capacity_type
  instance_types = var.instance_types
  desired_size   = var.desired_size
  min_size       = var.min_size
  max_size       = var.max_size

  # Jenkins plus any teammate ARNs listed in terraform.tfvars get kubectl access.
  cluster_admin_principals = merge(
    { jenkins = module.iam.jenkins_role_arn },
    { for arn in var.team_principal_arns : arn => arn }
  )

  tags = local.tags
}

###############################################################################
# CI AGENT  (Sprint 3)
# A Terraform-provisioned EC2 for Ansible to configure and Jenkins to build on.
# Off by default - turn on in terraform.tfvars once a public key is supplied.
###############################################################################

module "ci_agent" {
  source = "../../modules/ci-agent"
  count  = var.create_ci_agent ? 1 : 0

  name = local.name

  subnet_id             = module.vpc.public_subnet_ids[0]
  security_group_id     = module.vpc.jenkins_security_group_id
  instance_profile_name = module.iam.jenkins_instance_profile_name

  public_key    = var.ci_agent_public_key
  instance_type = var.ci_agent_instance_type

  tags = local.tags

  # An EC2 in a public subnet is only reachable once the internet gateway and
  # public route exist. Waiting on the whole VPC module guarantees that.
  depends_on = [module.vpc]
}
