output "jenkins_role_arn" {
  description = "ARN of the Jenkins EC2 role (map this into the EKS cluster)."
  value       = aws_iam_role.jenkins.arn
}

output "jenkins_role_name" {
  description = "Name of the Jenkins EC2 role."
  value       = aws_iam_role.jenkins.name
}

output "jenkins_instance_profile_name" {
  description = "Instance profile to attach to the Jenkins EC2 instance."
  value       = aws_iam_instance_profile.jenkins.name
}

output "account_id" {
  description = "AWS account ID."
  value       = data.aws_caller_identity.current.account_id
}
