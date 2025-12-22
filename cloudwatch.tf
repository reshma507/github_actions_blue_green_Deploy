resource "aws_cloudwatch_metric_alarm" "strapi_cpu_high" {
  alarm_name          = "strapi-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    ClusterName = aws_ecs_cluster.strapi.name
    ServiceName = aws_ecs_service.strapi.name
  }

  alarm_description = "High CPU usage on Strapi ECS service"
}
resource "aws_cloudwatch_metric_alarm" "strapi_memory_high" {
  alarm_name          = "strapi-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    ClusterName = aws_ecs_cluster.strapi.name
    ServiceName = aws_ecs_service.strapi.name
  }

  alarm_description = "High memory usage on Strapi ECS service"
}
resource "aws_cloudwatch_metric_alarm" "alb_latency_high" {
  alarm_name          = "strapi-alb-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 2

  dimensions = {
    LoadBalancer = aws_lb.strapi.arn_suffix
  }

  alarm_description = "High response latency on Strapi ALB"
}

resource "aws_cloudwatch_dashboard" "strapi_dashboard" {
  dashboard_name = "strapi-ecs-alb-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric",
        width = 12,
        height = 6,
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.strapi.name, "ServiceName", aws_ecs_service.strapi.name],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", aws_ecs_cluster.strapi.name, "ServiceName", aws_ecs_service.strapi.name]
          ],
          period = 60,
          stat   = "Average",
          region = var.aws_region,
          title  = "ECS CPU & Memory"
        }
      },
      {
        type = "metric",
        width = 12,
        height = 6,
        properties = {
          metrics = [
            ["AWS/ECS", "RunningTaskCount", "ClusterName", aws_ecs_cluster.strapi.name, "ServiceName", aws_ecs_service.strapi.name]
          ],
          period = 60,
          stat   = "Average",
          region = var.aws_region,
          title  = "Running Tasks"
        }
      },
      {
        type = "metric",
        width = 12,
        height = 6,
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.strapi.arn_suffix]
          ],
          period = 60,
          stat   = "Average",
          region = var.aws_region,
          title  = "ALB Response Latency"
        }
      }
    ]
  })
}

