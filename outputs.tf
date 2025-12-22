output "ecr_repository_url" {
  value = data.aws_ecr_repository.strapi.repository_url
}
output "rds_endpoint" {
  value = aws_db_instance.postgres.address
}
output "alb_dns_name" {
  value = aws_lb.strapi.dns_name
}
output "alb_dns_name" {
  value = aws_lb.strapi.dns_name
}

output "codedeploy_app" {
  value = aws_codedeploy_app.strapi.name
}
