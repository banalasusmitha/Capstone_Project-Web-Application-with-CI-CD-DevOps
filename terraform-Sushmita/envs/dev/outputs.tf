###############################################################################
# Everything the rest of the team needs from the infrastructure layer.
###############################################################################

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs - put the Jenkins EC2 instance here."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs - worker nodes live here."
  value       = module.vpc.private_subnet_ids
}

output "jenkins_security_group_id" {
  description = "Security group for the Jenkins EC2 instance (Kaushik)."
  value       = module.vpc.jenkins_security_group_id
}

output "jenkins_instance_profile_name" {
  description = "Attach this instance profile to the Jenkins EC2 instance - no access keys needed."
  value       = module.iam.jenkins_instance_profile_name
}

output "jenkins_role_arn" {
  description = "Jenkins IAM role ARN (already granted cluster-admin on EKS)."
  value       = module.iam.jenkins_role_arn
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version."
  value       = module.eks.cluster_version
}

output "node_group_name" {
  description = "Managed node group name."
  value       = module.eks.node_group_name
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA roles."
  value       = module.eks.oidc_provider_arn
}

output "ecr_repository_urls" {
  description = "ECR URLs for the Jenkinsfile and Kubernetes manifests."
  value       = var.create_ecr_repositories ? module.ecr[0].repository_urls : {}
}

output "app_ingress_paths" {
  description = "Paths the ShopNow services are served on once the ingress is created."
  value = {
    frontend = "/${var.app_user_name}"
    admin    = "/${var.app_user_name}-admin"
  }
}

output "docker_build_args" {
  description = "Build args Jenkins must pass so the React bundles resolve their assets and API base URL correctly."
  value       = "--build-arg USER_NAME=${var.app_user_name}"
}

output "kubeconfig_command" {
  description = "Run this to point kubectl at the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
