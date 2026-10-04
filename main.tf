terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS 리전 설정"
  type        = string
  default     = "ap-northeast-2"
}

variable "OPENAI_API_KEY" {
  description = "LiteLLM AI 게이트웨이에서 사용할 OpenAI API Key"
  type        = string
  sensitive   = true
}

# 1. VPC 생성
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "homegrown-vpc"
  }
}

# 2. 서브넷 생성
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "homegrown-public-subnet"
  }
}

# 3. 인터넷 게이트웨이
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "homegrown-igw"
  }
}

# 4. 라우팅 테이블
resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "homegrown-rt"
  }
}

resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.rt.id
}

# 5. 보안 그룹 (SSH: 22, LiteLLM AI Gateway: 4000)
resource "aws_security_group" "sg" {
  name        = "homegrown-ai-gateway-sg"
  description = "Allow SSH and LiteLLM AI Gateway traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "LiteLLM AI Gateway Port"
    from_port   = 4000
    to_port     = 4000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    ="-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "homegrown-sg"
  }
}

# 6. 최신 Ubuntu 22.04 LTS AMI 조회
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# 7. EC2 인스턴스 생성 및 LiteLLM 도커 배포 (User Data)
resource "aws_instance" "ai_gateway" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.sg.id]

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker

              # LiteLLM Docker 컨테이너 실행 (OpenAI API 키 주입)
              docker run -d \
                --name ai-gateway \
                --restart always \
                -p 4000:4000 \
                -e OPENAI_API_KEY="${var.OPENAI_API_KEY}" \
                ghcr.io/berriai/litellm:main-latest \
                --model gpt-4o
              EOF

  tags = {
    Name = "homegrown-ai-gateway"
  }
}

# 8. Output 출력 (GitHub Actions에서 사용)
output "ai_gateway_public_ip" {
  description = "AI 게이트웨이 인스턴스의 퍼블릭 IP"
  value       = aws_instance.ai_gateway.public_ip
}