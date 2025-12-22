
provider "aws" {
  region = var.aws_region
}

# ---------------- NETWORK ----------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ---------------- SECURITY GROUPS ----------------
resource "aws_security_group" "ecs_sg" {
  name   = "strapi-ecs-sg-reshma"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port       = 1337
    to_port         = 1337
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group" "rds_sg" {
  name   = "strapi-rds-sg-reshma"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "alb_sg" {
  name   = "strapi-alb-sg-reshma"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



# ---------------- RDS ----------------
resource "aws_db_subnet_group" "default" {
  name       = "strapi-db-subnet-reshma"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_instance" "postgres" {
  identifier             = "strapi-postgres-reshma"
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  allocated_storage      = var.db_allocated_storage
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
}

# ---------------- ECR ----------------
data "aws_ecr_repository" "strapi" {
  name = "strapi-app-reshma"
}

# ---------------- CLOUDWATCH ----------------
resource "aws_cloudwatch_log_group" "strapi" {
  name              = "/ecs/strapi-service-reshma"
  retention_in_days = 7
}
resource "aws_lb" "strapi" {
  name               = "strapi-alb-reshma"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}
resource "aws_lb_target_group" "strapi_blue" {
  name        = "strapi-tg-blue-reshma"
  port        = 1337
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/"
    matcher             = "200-399"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "strapi_green" {
  name        = "strapi-tg-green-reshma"
  port        = 1337
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/"
    matcher             = "200-399"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.strapi.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.strapi_blue.arn
  }
}


data "aws_iam_role" "ecs_execution_role" {
  name = "ecsTaskExecutionRole-reshma"
}
# resource "aws_iam_role" "codedeploy_role" {
#   name = "CodeDeployECSRole-reshma"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "codedeploy.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
# }

# resource "aws_iam_role_policy_attachment" "codedeploy_policy" {
#   role       = aws_iam_role.codedeploy_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
# }
data "aws_iam_role" "codedeploy_role" {
  name = "CodeDeployECSRole-reshma"
}
resource "aws_codedeploy_app" "strapi" {
  name             = "strapi-codedeploy-reshma"
  compute_platform = "ECS"
}



# ---------------- ECS ----------------
resource "aws_ecs_cluster" "strapi" {
  name = "strapi-cluster-reshma"
}

resource "aws_ecs_task_definition" "strapi" {
  family                   = "strapi-task-reshma"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  # execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  execution_role_arn = data.aws_iam_role.ecs_execution_role.arn


  depends_on = [aws_cloudwatch_log_group.strapi]

  container_definitions = jsonencode([
    {
      name  = "strapi-reshma"
      image = "${data.aws_ecr_repository.strapi.repository_url}:${var.image_tag}"

      essential = true

      portMappings = [{
        containerPort = 1337
        hostPort      = 1337
        protocol      = "tcp"
      }]

      environment = [
        { name = "HOST", value = "0.0.0.0" },
        { name = "PORT", value = "1337" },

        { name = "APP_KEYS", value = var.app_keys },
        { name = "API_TOKEN_SALT", value = var.api_token_salt },
        { name = "ADMIN_JWT_SECRET", value = var.admin_jwt_secret },
        { name = "TRANSFER_TOKEN_SALT", value = var.transfer_token_salt },
        { name = "ENCRYPTION_KEY", value = var.encryption_key },
        { name = "ADMIN_AUTH_SECRET", value = var.admin_auth_secret },
        { name = "NODE_TLS_REJECT_UNAUTHORIZED", value = "0" },

        { name = "DATABASE_CLIENT", value = "postgres" },
        { name = "DATABASE_HOST", value = aws_db_instance.postgres.address },
        { name = "DATABASE_PORT", value = "5432" },
        { name = "DATABASE_NAME", value = var.db_name },
        { name = "DATABASE_USERNAME", value = var.db_username },
        { name = "DATABASE_PASSWORD", value = var.db_password },
        { name = "DATABASE_SSL", value = "true" },
        { name = "DATABASE_SSL_REJECT_UNAUTHORIZED", value = "false" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/strapi-service-reshma"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "strapi-reshma"
        }
      }
    }
  ])
}
resource "aws_codedeploy_deployment_group" "strapi" {
  app_name              = aws_codedeploy_app.strapi.name
  deployment_group_name = "strapi-dg-reshma"
  service_role_arn      = data.aws_iam_role.codedeploy_role.arn

  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  deployment_config_name = "CodeDeployDefault.ECSCanary10Percent5Minutes"

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.strapi.name
    service_name = aws_ecs_service.strapi.name
  }

  blue_green_deployment_config {
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }

    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
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

  depends_on = [
    aws_ecs_service.strapi,
    aws_lb_listener.http
  ]
}



# resource "aws_ecs_service" "strapi" {
#   name            = "strapi-service-reshma"
#   cluster         = aws_ecs_cluster.strapi.id
#   task_definition = aws_ecs_task_definition.strapi.arn
#   desired_count   = 1
#   launch_type     = "FARGATE"

#   network_configuration {
#     subnets          = data.aws_subnets.default.ids
#     security_groups  = [aws_security_group.ecs_sg.id]
#     assign_public_ip = true
#   }

#   depends_on = [aws_db_instance.postgres]
# }
resource "aws_ecs_service" "strapi" {
  name          = "strapi-service-reshma"
  cluster       = aws_ecs_cluster.strapi.id
  task_definition = aws_ecs_task_definition.strapi.arn
  desired_count = 1

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.strapi_blue.arn
    container_name   = "strapi-reshma"
    container_port   = 1337
  }

  health_check_grace_period_seconds = 120

  depends_on = [aws_lb_listener.http]
}



# provider "aws" {
#   region = var.aws_region
# }

# # ---------------- NETWORK ----------------
# data "aws_vpc" "default" {
#   default = true
# }

# data "aws_subnets" "default" {
#   filter {
#     name   = "vpc-id"
#     values = [data.aws_vpc.default.id]
#   }
# }

# # ---------------- SECURITY GROUPS ----------------
# resource "aws_security_group" "ecs_sg" {
#   name   = "strapi-ecs-sg-reshma"
#   vpc_id = data.aws_vpc.default.id

#   ingress {
#     from_port   = 1337
#     to_port     = 1337
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

# resource "aws_security_group" "rds_sg" {
#   name   = "strapi-rds-sg-reshma"
#   vpc_id = data.aws_vpc.default.id

#   ingress {
#     from_port       = 5432
#     to_port         = 5432
#     protocol        = "tcp"
#     security_groups = [aws_security_group.ecs_sg.id]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }
# resource "aws_security_group" "alb_sg" {
#   name   = "strapi-alb-sg-reshma"
#   vpc_id = data.aws_vpc.default.id

#   ingress {
#     from_port   = 80
#     to_port     = 80
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }


# # ---------------- RDS ----------------
# resource "aws_db_subnet_group" "default" {
#   name       = "strapi-db-subnet-reshma"
#   subnet_ids = data.aws_subnets.default.ids
# }

# resource "aws_db_instance" "postgres" {
#   identifier             = "strapi-postgres-reshma"
#   engine                 = "postgres"
#   instance_class         = "db.t3.micro"
#   allocated_storage      = var.db_allocated_storage
#   db_name                = var.db_name
#   username               = var.db_username
#   password               = var.db_password
#   db_subnet_group_name   = aws_db_subnet_group.default.name
#   vpc_security_group_ids = [aws_security_group.rds_sg.id]
#   publicly_accessible    = false
#   skip_final_snapshot    = true
# }

# # ---------------- ECR ----------------
# data "aws_ecr_repository" "strapi" {
#   name = "strapi-app-reshma"
# }

# # ---------------- CLOUDWATCH ----------------
# resource "aws_cloudwatch_log_group" "strapi" {
#   name              = "/ecs/strapi-service-reshma"
#   retention_in_days = 7
# }
# resource "aws_lb" "strapi" {
#   name               = "strapi-alb-reshma"
#   internal           = false
#   load_balancer_type = "application"
#   security_groups    = [aws_security_group.alb_sg.id]
#   subnets            = data.aws_subnets.default.ids
# }
# resource "aws_lb_target_group" "strapi" {
#   name        = "strapi-tg-reshma"
#   port        = 1337
#   protocol    = "HTTP"
#   vpc_id      = data.aws_vpc.default.id
#   target_type = "ip"

#   health_check {
#     path                = "/admin"
#     healthy_threshold   = 2
#     unhealthy_threshold = 2
#     timeout             = 5
#     interval            = 30
#     matcher             = "200-399"
#   }
# }
# resource "aws_lb_listener" "http" {
#   load_balancer_arn = aws_lb.strapi.arn
#   port              = 80
#   protocol          = "HTTP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.strapi.arn
#   }
# }
 

# # ---------------- IAM ----------------
# # resource "aws_iam_role" "ecs_execution_role" {
# #   name = "ecsTaskExecutionRole-reshma"

# #   assume_role_policy = jsonencode({
# #     Version = "2012-10-17"
# #     Statement = [{
# #       Effect    = "Allow"
# #       Principal = { Service = "ecs-tasks.amazonaws.com" }
# #       Action    = "sts:AssumeRole"
# #     }]
# #   })
# # }

# data "aws_iam_role" "ecs_execution_role" {
#   name = "ecsTaskExecutionRole-reshma"
# }

# # resource "aws_iam_role_policy_attachment" "ecs_policy" {
# #   role       = aws_iam_role.ecs_execution_role.name
# #   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
# # }

# # ---------------- ECS ----------------
# resource "aws_ecs_cluster" "strapi" {
#   name = "strapi-cluster-reshma"
# }

# resource "aws_ecs_task_definition" "strapi" {
#   family                   = "strapi-task-reshma"
#   requires_compatibilities = ["FARGATE"]
#   network_mode             = "awsvpc"
#   cpu                      = "512"
#   memory                   = "1024"
#   # execution_role_arn       = aws_iam_role.ecs_execution_role.arn
#   execution_role_arn = data.aws_iam_role.ecs_execution_role.arn


#   depends_on = [aws_cloudwatch_log_group.strapi]

#   container_definitions = jsonencode([
#     {
#       name  = "strapi-reshma"
#       image = "${data.aws_ecr_repository.strapi.repository_url}:${var.image_tag}"

#       essential = true

#       portMappings = [{
#         containerPort = 1337
#         hostPort      = 1337
#         protocol      = "tcp"
#       }]

#       environment = [
#         { name = "HOST", value = "0.0.0.0" },
#         { name = "PORT", value = "1337" },

#         { name = "APP_KEYS", value = var.app_keys },
#         { name = "API_TOKEN_SALT", value = var.api_token_salt },
#         { name = "ADMIN_JWT_SECRET", value = var.admin_jwt_secret },
#         { name = "TRANSFER_TOKEN_SALT", value = var.transfer_token_salt },
#         { name = "ENCRYPTION_KEY", value = var.encryption_key },
#         { name = "ADMIN_AUTH_SECRET", value = var.admin_auth_secret },
#         { name = "NODE_TLS_REJECT_UNAUTHORIZED", value = "0" },

#         { name = "DATABASE_CLIENT", value = "postgres" },
#         { name = "DATABASE_HOST", value = aws_db_instance.postgres.address },
#         { name = "DATABASE_PORT", value = "5432" },
#         { name = "DATABASE_NAME", value = var.db_name },
#         { name = "DATABASE_USERNAME", value = var.db_username },
#         { name = "DATABASE_PASSWORD", value = var.db_password },
#         { name = "DATABASE_SSL", value = "true" },
#         { name = "DATABASE_SSL_REJECT_UNAUTHORIZED", value = "false" }
#       ]

#       logConfiguration = {
#         logDriver = "awslogs"
#         options = {
#           awslogs-group         = "/ecs/strapi-service-reshma"
#           awslogs-region        = var.aws_region
#           awslogs-stream-prefix = "strapi-reshma"
#         }
#       }
#     }
#   ])
# }

# # resource "aws_ecs_service" "strapi" {
# #   name            = "strapi-service-reshma"
# #   cluster         = aws_ecs_cluster.strapi.id
# #   task_definition = aws_ecs_task_definition.strapi.arn
# #   desired_count   = 1
# #   launch_type     = "FARGATE"

# #   network_configuration {
# #     subnets          = data.aws_subnets.default.ids
# #     security_groups  = [aws_security_group.ecs_sg.id]
# #     assign_public_ip = true
# #   }

# #   depends_on = [aws_db_instance.postgres]
# # }
# resource "aws_ecs_service" "strapi" {
#   name            = "strapi-service-reshma"
#   cluster         = aws_ecs_cluster.strapi.id
#   task_definition = aws_ecs_task_definition.strapi.arn
#   desired_count   = 1
#   launch_type     = "FARGATE"

#   network_configuration {
#     subnets          = data.aws_subnets.default.ids
#     security_groups  = [aws_security_group.ecs_sg.id]
#     assign_public_ip = true
#   }

#   load_balancer {
#     target_group_arn = aws_lb_target_group.strapi.arn
#     container_name   = "strapi-reshma"
#     container_port   = 1337
#   }

#   depends_on = [
#     aws_lb_listener.http,
#     aws_db_instance.postgres
#   ]
# }

# provider "aws" {
#   region = var.aws_region
# }

# # ---------------- NETWORK ----------------
# data "aws_vpc" "default" {
#   default = true
# }

# data "aws_subnets" "default" {
#   filter {
#     name   = "vpc-id"
#     values = [data.aws_vpc.default.id]
#   }
# }

# # ---------------- SECURITY GROUPS ----------------
# resource "aws_security_group" "ecs_sg" {
#   name   = "strapi-ecs-sg"
#   vpc_id = data.aws_vpc.default.id

#   ingress {
#     from_port   = 1337
#     to_port     = 1337
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

# resource "aws_security_group" "rds_sg" {
#   name   = "strapi-rds-sg"
#   vpc_id = data.aws_vpc.default.id

#   ingress {
#     from_port       = 5432
#     to_port         = 5432
#     protocol        = "tcp"
#     security_groups = [aws_security_group.ecs_sg.id]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

# # ---------------- RDS ----------------
# resource "aws_db_subnet_group" "default" {
#   name       = "strapi-db-subnet"
#   subnet_ids = data.aws_subnets.default.ids
# }

# resource "aws_db_instance" "postgres" {
#   identifier             = "strapi-postgres"
#   engine                 = "postgres"
#   instance_class         = "db.t3.micro"
#   allocated_storage      = var.db_allocated_storage
#   db_name                = var.db_name
#   username               = var.db_username
#   password               = var.db_password
#   db_subnet_group_name   = aws_db_subnet_group.default.name
#   vpc_security_group_ids = [aws_security_group.rds_sg.id]
#   publicly_accessible    = false
#   skip_final_snapshot    = true
# }

# data "aws_ecr_repository" "strapi" {
#   name = "strapi-app"
# }

# # resource "aws_ecr_repository" "strapi" {
# #   name = "strapi-app"

# #   lifecycle {
# #     prevent_destroy = false
# #     ignore_changes  = [repository_url]  # Terraform won't fail if repo already exists
# #   }
# # }

# # ---------------- CLOUDWATCH LOG GROUP ----------------
# resource "aws_cloudwatch_log_group" "strapi" {
#   name              = "/ecs/strapi-service"
#   retention_in_days = 7
# }



# # ---------------- IAM ----------------
# resource "aws_iam_role" "ecs_execution_role" {
#   name = "ecsTaskExecutionRole"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "ecs-tasks.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
# }

# resource "aws_iam_role_policy_attachment" "ecs_policy" {
#   role       = aws_iam_role.ecs_execution_role.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
# }

# # resource "aws_iam_role_policy_attachment" "secrets_policy" {
# #   role       = aws_iam_role.ecs_execution_role.name
# #   policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
# # }

# # ---------------- ECS ----------------
# resource "aws_ecs_cluster" "strapi" {
#   name = "strapi-cluster"
# }


# resource "aws_ecs_task_definition" "strapi" {
#   family                   = "strapi-task"
#   requires_compatibilities = ["FARGATE"]
#   network_mode             = "awsvpc"
#   cpu                      = "512"
#   memory                   = "1024"
#   execution_role_arn       = aws_iam_role.ecs_execution_role.arn

#   depends_on = [
#     aws_cloudwatch_log_group.strapi
#   ]

#   container_definitions = jsonencode([
#     {
#       name  = "strapi"
#      image = "${data.aws_ecr_repository.strapi.repository_url}:${var.image_tag}"


#       essential = true

#       portMappings = [
#         {
#           containerPort = 1337
#           hostPort      = 1337
#           protocol      = "tcp"
#         }
#       ] 
#       environment = [
#        # Server
#         { name = "HOST", value = "0.0.0.0" },
#         { name = "PORT", value = "1337" },

#         # Strapi Secrets (same as docker run)
#         { name = "APP_KEYS", value = var.app_keys },
#         { name = "API_TOKEN_SALT", value = var.api_token_salt },
#         { name = "ADMIN_JWT_SECRET", value = var.admin_jwt_secret },
#         { name = "TRANSFER_TOKEN_SALT", value = var.transfer_token_salt },
#         { name = "ENCRYPTION_KEY", value = var.encryption_key },
#         { name = "ADMIN_AUTH_SECRET", value = var.admin_auth_secret },
#         { name = "NODE_TLS_REJECT_UNAUTHORIZED", value = "0" },

#         { name = "DATABASE_CLIENT", value = "postgres" },
#         { name = "DATABASE_HOST", value = aws_db_instance.postgres.address },
#         { name = "DATABASE_PORT", value = "5432" },
#         { name = "DATABASE_NAME", value = var.db_name },
#         { name = "DATABASE_USERNAME", value = var.db_username },
#         { name = "DATABASE_PASSWORD", value = var.db_password },


#         { name = "DATABASE_SSL", value = "true" },
#         { name = "DATABASE_SSL_REJECT_UNAUTHORIZED", value = "false" }
#       ]


#       logConfiguration = {
#         logDriver = "awslogs"
#         options = {
#           "awslogs-group"         = "/ecs/strapi-service"
#           "awslogs-region"        = var.aws_region
#           "awslogs-stream-prefix" = "strapi"
#         }
#       }

#       healthCheck = {
#         command     = ["CMD-SHELL", "curl -f http://localhost:1337 || exit 1"]
#         interval    = 30
#         timeout     = 5
#         retries     = 3
#         startPeriod = 60
#       }
#     }
#   ])
# }


# resource "aws_ecs_service" "strapi" {
#   name            = "strapi-service"
#   cluster         = aws_ecs_cluster.strapi.id
#   task_definition = aws_ecs_task_definition.strapi.arn
#   desired_count   = 1
#   launch_type     = "FARGATE"

#   network_configuration {
#     subnets         = data.aws_subnets.default.ids
#     security_groups = [aws_security_group.ecs_sg.id]
#     assign_public_ip = true
#   }

#   depends_on = [aws_db_instance.postgres]
# }
