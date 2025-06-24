terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  required_version = ">= 1.5.0"
}

provider "aws" {
  region = "ap-south-1"
}

variable "vpc_cidr"    { default = "10.0.0.0/16" }
variable "db_username" { default = "admin" }
variable "db_password" { default = "MySecurePass123" }
variable "db_name"     { default = "inventory" }
variable "azs"         { default = ["ap-south-1a", "ap-south-1b"] }

locals {
  public_subnets  = ["10.0.0.0/20", "10.0.48.0/20"]
  private_subnets = ["10.0.16.0/20", "10.0.32.0/20", "10.0.64.0/20", "10.0.80.0/20"]
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "east2-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "east2-igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnets[count.index]
  map_public_ip_on_launch = true
  availability_zone       = var.azs[count.index]
  tags                    = { Name = "public-subnet-${count.index + 1}" }
}

resource "aws_subnet" "private" {
  count                   = 4
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.private_subnets[count.index]
  map_public_ip_on_launch = false
  availability_zone       = element(var.azs, count.index % 2)
  tags                    = { Name = "private-subnet-${count.index + 1}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "public-rt" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "private-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "nat-gateway" }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 4
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Group for RDS
resource "aws_security_group" "db" {
  name        = "rds-db-sg"
  vpc_id      = aws_vpc.main.id
  description = "Allow MySQL from anywhere (adjust for prod)"
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "rds-db-sg" }
}

# RDS Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "my-db-subnet-group"
  subnet_ids = [aws_subnet.private[0].id, aws_subnet.private[1].id]
  tags       = { Name = "my-db-subnet-group" }
}

# RDS Instance
resource "aws_db_instance" "mysql" {
  identifier              = "mysqldatabase"
  allocated_storage       = 20
  engine                  = "mysql"
  engine_version          = "8.0.41"
  instance_class          = "db.t3.small"
  db_name                 = var.db_name
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  publicly_accessible     = true
  multi_az                = true
  skip_final_snapshot     = true
  tags                    = { Name = "my-mysql-db" }
}

# IAM Roles for EKS
data "aws_iam_policy_document" "eks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster_role" {
  name               = "EKSClusterRole-v2"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role.json
  tags               = { Name = "eks-cluster-role" }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn_
