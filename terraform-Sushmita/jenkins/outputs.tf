output "jenkins_url" {
  description = "Open this in a browser once Jenkins is installed."
  value       = "http://${aws_eip.jenkins.public_ip}:8080"
}

output "public_ip" {
  description = "Fixed public IP of the Jenkins server."
  value       = aws_eip.jenkins.public_ip
}

output "ssh_command" {
  description = "SSH in (private key stays on your machine)."
  value       = "ssh -i ~/.ssh/shopnow-ci-agent ec2-user@${aws_eip.jenkins.public_ip}"
}

output "ansible_inventory" {
  description = "Static inventory line for an Ansible playbook that installs Jenkins."
  value       = "${aws_eip.jenkins.public_ip} ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/shopnow-ci-agent"
}

output "role_arn" {
  description = "IAM role of the server. envs/dev grants it kubectl admin automatically."
  value       = aws_iam_role.jenkins.arn
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.jenkins.id
}
