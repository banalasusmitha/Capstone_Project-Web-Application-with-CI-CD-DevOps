output "state_bucket_name" {
  description = "Put this in envs/dev/backend.hcl as `bucket`."
  value       = aws_s3_bucket.tf_state.id
}

output "state_bucket_region" {
  description = "Put this in envs/dev/backend.hcl as `region`."
  value       = var.aws_region
}

output "lock_table_name" {
  description = "DynamoDB lock table name (empty when S3 native locking is used)."
  value       = var.create_dynamodb_lock_table ? aws_dynamodb_table.tf_lock[0].name : ""
}
