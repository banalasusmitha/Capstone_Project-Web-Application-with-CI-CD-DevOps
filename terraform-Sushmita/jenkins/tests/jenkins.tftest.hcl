# Tests for the Jenkins server stack. Run with: terraform test
# Mock provider only - never calls AWS, creates nothing, costs nothing.

mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = { id = "vpc-default" }
  }
  mock_data "aws_subnets" {
    defaults = { ids = ["subnet-bbb", "subnet-aaa"] }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::095355901688:role/shopnow-jenkins-server-role" }
  }
  mock_resource "aws_eip" {
    defaults = { public_ip = "13.200.1.2" }
  }
}

run "server_builds_with_expected_outputs" {
  command = apply

  assert {
    condition     = output.jenkins_url == "http://13.200.1.2:8080"
    error_message = "Jenkins URL should use the Elastic IP on port 8080"
  }
  assert {
    condition     = aws_iam_role.jenkins.name == "shopnow-jenkins-server-role"
    error_message = "Role name must match what envs/dev looks up"
  }
  assert {
    condition     = aws_instance.jenkins.subnet_id == "subnet-aaa"
    error_message = "Subnet choice should be stable (sorted)"
  }
  assert {
    condition     = aws_instance.jenkins.root_block_device[0].delete_on_termination == true
    error_message = "Disk must be deleted with the server - no orphaned volumes"
  }
}

run "rejects_private_key_pasted_by_mistake" {
  command = plan
  variables {
    public_key = "-----BEGIN OPENSSH PRIVATE KEY-----"
  }
  expect_failures = [var.public_key]
}
