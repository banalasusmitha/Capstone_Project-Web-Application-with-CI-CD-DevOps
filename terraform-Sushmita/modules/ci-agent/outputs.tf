output "instance_id" {
  description = "EC2 instance ID of the CI agent."
  value       = aws_instance.agent.id
}

output "public_ip" {
  description = "Public IP - what Ansible connects to."
  value       = aws_instance.agent.public_ip
}

output "private_ip" {
  description = "Private IP inside the VPC."
  value       = aws_instance.agent.private_ip
}

output "ssh_user" {
  description = "Default login user on Amazon Linux 2023."
  value       = "ec2-user"
}

output "key_name" {
  description = "Name of the EC2 key pair."
  value       = aws_key_pair.agent.key_name
}
