resource "aws_codedeploy_app" "ecs" {
  name             = "strapi-codedeploy-reshma"
  compute_platform = "ECS"
}
data "aws_iam_role" "codedeploy_role" {
  name = "CodeDeployECSRole-reshma"
}


resource "aws_codedeploy_deployment_group" "ecs" {
  app_name              = aws_codedeploy_app.ecs.name
  deployment_group_name = "strapi-dg-reshma"
  service_role_arn      = data.aws_iam_role.codedeploy_role.arn

  deployment_config_name = "CodeDeployDefault.ECSCanary10Percent5Minutes"

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.strapi.name
    service_name = aws_ecs_service.strapi.name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.http.arn]
      }

      target_group {
        name = aws_lb_target_group.strapi_blue.name
      }

      target_group {
        name = aws_lb_target_group.strapi_green.name
      }
    }
  }
}
