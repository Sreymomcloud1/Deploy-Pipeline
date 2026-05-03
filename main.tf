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

# 1. SSH Key
resource "aws_key_pair" "labsuserrr" {
  key_name   = "labsuserrr"
  public_key = file("${path.module}/labsuser.pub") 
}

# 2. Networking
resource "aws_default_vpc" "default" {}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [aws_default_vpc.default.id]
  }
}

# 3. Security Group for ALB
resource "aws_security_group" "alb_sg" {
  name        = "ALB-SG"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_default_vpc.default.id

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

# 4. Security Group for EC2
resource "aws_security_group" "MySG" {
  name        = "EC2-App-SG"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
    from_port       = 5000
    to_port         = 5000
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

# 5. Launch Template
resource "aws_launch_template" "app_lt" {
  name_prefix   = "app-launch-template-"
  image_id      = "ami-0ec10929233384c7f" 
  instance_type = "t3.micro"
  key_name      = aws_key_pair.labsuserrr.key_name
  
  network_interfaces {
    security_groups             = [aws_security_group.MySG.id]
    associate_public_ip_address = false # Resolved hotspot from image_fe327d.png
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

# 6. ALB Resources
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

# The resource from your screenshot
resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = "80"
  protocol          = "HTTP" # SonarCloud Hotspot: Manual review required if not using SSL

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# 7. ASG
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

output "website_url" {
  value = "http://${aws_lb.app_lb.dns_name}"
}
