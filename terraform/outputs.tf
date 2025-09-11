output "alb_dns_name"         { value = aws_lb.app_alb.dns_name }
output "rds_endpoint"         { value = aws_db_instance.app_db.address }
output "ecr_repo_url"         { value = aws_ecr_repository.app.repository_url }
output "caller_account_id"    { value = data.aws_caller_identity.current.account_id }
