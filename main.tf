terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# -----------------------------
# KEY PAIR
# -----------------------------
resource "aws_key_pair" "labsuserrr" {
  key_name   = "labsuserrr"
  public_key = file("${path.module}/labsuser.pub")
}

# -----------------------------
# DEFAULT VPC + SUBNETS
# -----------------------------
resource "aws_default_vpc" "default" {}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [aws_default_vpc.default.id]
  }
}

# -----------------------------
# ALB SECURITY GROUP (PUBLIC)
# -----------------------------
resource "aws_security_group" "alb_sg" {
  name        = "ALB-SG"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Required for browser access
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------
# EC2 SECURITY GROUP (SECURE)
# -----------------------------
resource "aws_security_group" "MySG" {
  name        = "EC2-App-SG"
  description = "Allow ALB + restricted SSH + monitoring"
  vpc_id      = aws_default_vpc.default.id

  # 🔒 FIX: Restrict SSH (CHANGE THIS TO YOUR IP)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["YOUR_IP/32"]
  }

  # Only ALB can access app
  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Node Exporter ONLY inside VPC (for Prometheus)
  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------
# LAUNCH TEMPLATE
# -----------------------------
resource "aws_launch_template" "app_lt" {
  name_prefix   = "app-launch-template-"
  image_id      = "ami-0ec10929233384c7f"
  instance_type = "t3.micro"
  key_name      = aws_key_pair.labsuserrr.key_name

  network_interfaces {
    security_groups = [aws_security_group.MySG.id]

    # tfsec:ignore:AWS006
    # Public IP required for ALB-based access in this lab/demo
    associate_public_ip_address = true
  }

  # 🔒 SECURITY: Enforce IMDSv2
  metadata_options {
    http_tokens = "required"
  }

  # 🔒 SECURITY: Encrypt disk
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = 8
      volume_type = "gp3"
      encrypted   = true
    }
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io

    systemctl start docker
    systemctl enable docker
    usermod -aG docker ubuntu

    # Run app
    docker pull sophearumsiyonn/deploy-pipeline:v1.0
    docker run -d -p 5000:5000 --name deploy-app sophearumsiyonn/deploy-pipeline:v1.0

    # Run node exporter
    docker run -d -p 9100:9100 --name node-exporter prom/node-exporter:latest
  EOF
  )
}

# -----------------------------
# LOAD BALANCER
# -----------------------------
resource "aws_lb" "app_lb" {
  name               = "app-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

# -----------------------------
# TARGET GROUP
# -----------------------------
resource "aws_lb_target_group" "app_tg" {
  name     = "app-target-group"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_default_vpc.default.id

  health_check {
    path     = "/"
    protocol = "HTTP"
    matcher  = "200-399"
  }
}

# -----------------------------
# LISTENER
# -----------------------------
resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# -----------------------------
# AUTO SCALING GROUP
# -----------------------------
resource "aws_autoscaling_group" "app_asg" {
  name                = "app-autoscaling-group"
  vpc_zone_identifier = data.aws_subnets.default.ids
  target_group_arns   = [aws_lb_target_group.app_tg.arn]

  min_size         = 1
  desired_capacity = 1
  max_size         = 3

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "WebServer-ASG-Instance"
    propagate_at_launch = true
  }
}

# -----------------------------
# AUTO SCALING POLICY
# -----------------------------
resource "aws_autoscaling_policy" "cpu_policy" {
  name                   = "cpu-scaling-policy"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 10.0
  }
}

# -----------------------------
# OUTPUT
# -----------------------------
output "website-url" {
  value = "http://${aws_lb.app_lb.dns_name}"
}
