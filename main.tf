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
# terraform {
#   backend "s3" {
#     bucket         = "strapi-terraform-state-reshma"
#     key            = "ecs/terraform.tfstate"
#     region         = "eu-north-1"
#     encrypt        = true
#   }
# }


# ---------------- SECURITY GROUPS ----------------

# ALB Security Group (CHANGED: added HTTPS 443)
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

# ECS Security Group (ALB → ECS on 1337)
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

# RDS Security Group
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

# ---------------- ALB ----------------
resource "aws_lb" "strapi" {
  name               = "strapi-alb-reshma"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "strapi_blue" {
  name        = "strapi-blue-tg-reshma"
  port        = 1337
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/"
    matcher             = "200,204,301,302"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}


resource "aws_lb_target_group" "strapi_green" {
  name        = "strapi-green-tg-reshma"
  port        = 1337
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/"
    matcher             = "200,204,301,302"
    interval            = 30
    timeout             = 5
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



# ---------------- IAM ----------------
 data "aws_iam_role" "ecs_execution_role" {
  name = "ecsTaskExecutionRole-reshma"
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
  execution_role_arn       = data.aws_iam_role.ecs_execution_role.arn

  depends_on = [aws_cloudwatch_log_group.strapi]

  # CHANGED: valid dynamic image (NO placeholder error)
  container_definitions = jsonencode([
    {
      name      = "strapi-reshma"
      image     = "${data.aws_ecr_repository.strapi.repository_url}:${var.image_tag}"
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

resource "aws_ecs_service" "strapi" {
  name            = "strapi-service-reshma"
  cluster         = aws_ecs_cluster.strapi.id
  task_definition = aws_ecs_task_definition.strapi.arn  # REQUIRED at creation
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  health_check_grace_period_seconds = 60

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

  lifecycle {
    ignore_changes = [
      task_definition,   # CodeDeploy manages this
      load_balancer      # CodeDeploy swaps TGs
    ]
  }

  depends_on = [aws_lb_listener.http]
}



# resource "aws_ecs_service" "strapi" {
#   name            = "strapi-service-reshma"
#   cluster         = aws_ecs_cluster.strapi.id
#   task_definition = aws_ecs_task_definition.strapi.arn
#   desired_count   = 1
#   launch_type     = "FARGATE"

#   deployment_controller {
#     type = "CODE_DEPLOY"
#   }
 
#  health_check_grace_period_seconds = 60
#   network_configuration {
#     subnets          = data.aws_subnets.default.ids
#     security_groups  = [aws_security_group.ecs_sg.id]
#     assign_public_ip = true
#   }

#   load_balancer {
#     target_group_arn = aws_lb_target_group.strapi_blue.arn
#     container_name   = "strapi-reshma"
#     container_port   = 1337
#   }

#   depends_on = [aws_lb_listener.http]
# }

#         # { name = "NODE_TLS_REJECT_UNAUTHORIZED", value = "0" },

        