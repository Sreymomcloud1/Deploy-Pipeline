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

# Key pair for EC2
resource "aws_key_pair" "labsuserrr" {
  key_name   = "labsuserrr"
  public_key = file("${path.module}/labsuser.pub")
}

# Security group for EC2
resource "aws_security_group" "MySG" {
  name        = "EC2-App-SG"
  description = "Allow SSH, App Port, and Node Exporter"
  vpc_id      = aws_default_vpc.default.id

  # FIX 1: Restricting SSH to a specific CIDR (e.g., a VPN or your IP) 
  # helps move the Security Rating toward 'A'. 
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"] # Example: Internal network only
  }

  # FIX 2: Removed semicolons to fix the "Unable to parse" error
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
    cidr_blocks = ["172.31.0.0/16"] # Restricted to VPC range
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_default_vpc" "default" {}

# Launch template
resource "aws_launch_template" "app_lt" {
  name_prefix   = "app-launch-template-"
  image_id      = "ami-0ec10929233384c7f" 
  instance_type = "t3.micro"
  key_name      = aws_key_pair.labsuserrr.key_name

  network_interfaces {
    security_groups             = [aws_security_group.MySG.id]
    # FIX 3: Set to 'false' to resolve the Hotspot in image_1969bf.png.
    # If you need public access, keep it 'true' but mark it 'Safe' in SonarCloud.
    associate_public_ip_address = false 
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ubuntu
    docker pull 143mom/deploy-pipeline:v1.0
    docker run --name deploy-app -d -p 5000:5000 143mom/deploy-pipeline:v1.0
    docker run -d \
      --name node-exporter \
      -p 9100:9100 \
      prom/node-exporter:latest
  EOF
  )
}
