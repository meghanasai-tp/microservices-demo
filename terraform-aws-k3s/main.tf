terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "region" {
  default = "ap-southeast-2"
}

variable "key_name" {
  description = "Name of your existing EC2 key pair"
  default = "meghana"
}

provider "aws" {
  region = var.region
}

# Latest Ubuntu 24.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners = ["099720109477"] # Canonical

  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_security_group" "k3s_sg" {
  name = "k3s-online-boutique-sg"
  description = "SSH and Online Boutique access"

  ingress {
    description = "SSH"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Online Boutique NodePort"
    from_port = 30080
    to_port = 30080
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "k3s" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  key_name = var.key_name
  vpc_security_group_ids = [aws_security_group.k3s_sg.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  # Installs k3s, deploys Online Boutique, exposes frontend on NodePort 30080
  user_data = <<-EOT
    #!/bin/bash
    curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
    until k3s kubectl get nodes 2>/dev/null | grep -q " Ready"; do sleep 5; done
    k3s kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml
    sleep 20
    k3s kubectl patch svc frontend-external -p '{"spec":{"type":"NodePort","ports":[{"port":80,"targetPort":8080,"nodePort":30080}]}}'
  EOT

  tags = {
    Name = "terraform-k3s-online-boutique"
  }
}

output "public_ip" {
  value = aws_instance.k3s.public_ip
}

output "app_url" {
  value = "http://${aws_instance.k3s.public_ip}:30080"
}
