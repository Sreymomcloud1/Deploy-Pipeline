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

# Key pair for the FoodExpress EC2 instances
resource "aws_key_pair" "labsuserrr" {
  key_name   = "labsuserrr"
  public_key = file("${path.module}/labsuser.pub")
}

# Security group for EC2
resource "aws_security_group" "MySG" {
  name        = "EC2-App-SG"
  description = "Allow restricted SSH and App traffic"
  vpc_id      = aws_default_vpc.default.id

  # Security Fix: SSH restricted to a specific IP or internal range 
  # (Change '1.2.3.4/32' to your actual IP to satisfy SonarQube)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # SonarQube will flag this; use a specific IP for an 'A' rating.
  }

  # Best Practice: Only allow traffic from the Load Balancer security group
  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"] # Restricted to VPC internal range for Node Exporter
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_default_vpc" "default" {}

# Launch template for the Sourcely/FoodExpress application
resource "aws_launch_template" "app_lt" {
  name_prefix   = "app-launch-template-"
  image_id      = "ami-0ec10929233384c7f" 
  instance_type = "t3.micro"
  key_name      = aws_key_pair.labsuserrr.key_name

  network_interfaces {
    security_groups             = [aws_security_group.MySG.id]
    associate_public_ip_address = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ubuntu
    # Using the specific image version built in the pipeline
    docker pull 143mom/deploy-pipeline:v1.0
    docker run --name deploy-app -d -p 5000:5000 143mom/deploy-pipeline:v1.0
    docker run -d \
      --name node-exporter \
      -p 9100:9100 \
      prom/node-exporter:latest
  EOF
  )
}
