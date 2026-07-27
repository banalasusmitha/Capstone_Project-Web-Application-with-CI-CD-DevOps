output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the control plane."
  value       = aws_eks_cluster.this.version
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA certificate for the cluster."
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group EKS created for control plane <-> node traffic."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider (used for IRSA roles)."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "node_group_name" {
  description = "Name of the managed node group."
  value       = aws_eks_node_group.this.node_group_name
}

output "node_role_arn" {
  description = "IAM role assumed by the worker nodes."
  value       = aws_iam_role.node.arn
}
