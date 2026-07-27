output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = aws_subnet.private[*].id
}

output "azs" {
  description = "Availability Zones in use."
  value       = local.azs
}

output "jenkins_security_group_id" {
  description = "Security group for the Jenkins EC2 instance."
  value       = aws_security_group.jenkins.id
}

output "eks_control_plane_extra_sg_id" {
  description = "Additional security group attached to the EKS control plane."
  value       = aws_security_group.eks_control_plane_extra.id
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs (empty when NAT is disabled)."
  value       = aws_nat_gateway.this[*].id
}
