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

# 1. SSH Key Pair
resource "aws_key_pair" "labsuserrr" {
  key_name   = "labsuserrr"
  public_key = file("${path.module}/labsuser.pub") 
}

# 2. Networking Context
resource "aws_default_vpc" "default" {}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [aws_default_vpc.default.id]
  }
}

# 3. Security Group for Load Balancer (Public Facing)
resource "aws_security_group" "alb_sg" {
  name        = "ALB-SG"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Public HTTP access is allowed
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 4. Security Group for EC2 (Private Application Tier)
resource "aws_security_group" "MySG" {
  name        = "EC2-App-SG"
  description = "Restricted ingress for Security Rating A"
  vpc_id      = aws_default_vpc.default.id

  # FIX for Security Rating A: Restrict SSH to a private range 
  # SonarCloud flags 0.0.0.0/0 on Port 22 as a 'B' rating or lower.
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"] 
  }

  # Allow application traffic ONLY from the Load Balancer
  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Restrict Node Exporter to your internal VPC range
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

# 5. Launch Template (Fixes Hotspot in image_fe327d.png)
resource "aws_launch_template" "app_lt" {
  name_prefix   = "app-lt-"
  image_id      = "ami-0ec10929233384c7f" 
  instance_type = "t3.micro"
  key_name      = aws_key_pair.labsuserrr.key_name
  
  network_interfaces {
    security_groups             = [aws_security_group.MySG.id]
    # Required Fix for Hotspot: No public IP on the instance
    associate_public_ip_address = false 
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io
              systemctl start docker
              usermod -aG docker ubuntu
              docker pull 143mom/deploy-pipeline:v1.0
              docker run --name deploy-app -d -p 5000:5000 143mom/deploy-pipeline:v1.0
              EOF
  )
}

# 6. Load Balancer Configuration (The "Public" Gate)
resource "aws_lb" "app_lb" {
  name               = "app-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "app_tg" {
  name     = "app-target-group"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_default_vpc.default.id

  health_check {
    path = "/"
    port = "5000"
  }
}

resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# 7. Auto Scaling Group
resource "aws_autoscaling_group" "app_asg" {
  name                = "app-asg"
  vpc_zone_identifier = data.aws_subnets.default.ids
  target_group_arns   = [aws_lb_target_group.app_tg.arn]
  min_size            = 1
  max_size            = 2

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }
}

# Output
output "website_url" {
  value = "http://${aws_lb.app_lb.dns_name}"
}
