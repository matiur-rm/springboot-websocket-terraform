provider "aws" {
  region = var.aws_region
}

# ECR Repository for Docker images
resource "aws_ecr_repository" "websocket_app" {
  name = "spring-websocket-app"
}

# ECS Cluster
resource "aws_ecs_cluster" "cluster" {
  name = "websocket-cluster"
}

# ECS Task Definition (Fargate)
resource "aws_ecs_task_definition" "task" {
  family                   = "websocket-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512    # 0.5 vCPU
  memory                   = 1024   # 1GB RAM
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name      = "websocket-app",
    image     = "${aws_ecr_repository.websocket_app.repository_url}:latest",
    essential = true,
    portMappings = [{
      containerPort = 8080,
      hostPort      = 8080,
      protocol      = "tcp"
    }],
    environment = [
      { name = "SERVER_PORT", value = "8080" }
    ],
    logConfiguration = {
      logDriver = "awslogs",
      options = {
        "awslogs-group"         = "/ecs/websocket-app",
        "awslogs-region"        = var.aws_region,
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# ECS Service
resource "aws_ecs_service" "service" {
  name            = "websocket-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = aws_subnet.public.*.id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true  # Required for Fargate in public subnets
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "websocket-app"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http]
}

# ALB with WebSocket support
resource "aws_lb" "alb" {
  name               = "websocket-alb"
  load_balancer_type = "application"
  subnets            = aws_subnet.public.*.id
  security_groups    = [aws_security_group.alb.id]
}

# Target Group (HTTP, not HTTPS, for simplicity)
resource "aws_lb_target_group" "tg" {
  name        = "websocket-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/actuator/health"  # Spring Boot Actuator endpoint
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}

# ALB Listener (HTTP port 80 → Target Group)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# Security Group for ALB (allow HTTP/WebSocket)
resource "aws_security_group" "alb" {
  name   = "websocket-alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
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

# Security Group for ECS (allow traffic from ALB only)
resource "aws_security_group" "ecs" {
  name   = "websocket-ecs-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# VPC and Subnets (minimal setup)
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index}.0/24"
  availability_zone = "${var.aws_region}${count.index == 0 ? "a" : "b"}"
}

# IAM Role for ECS
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}