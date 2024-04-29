
provider "aws" {
  region = "us-east-1"

  # ... Additional provider configuration   
}

# vpc.tf - Define Your VPC and Public Subnets
resource "aws_vpc" "base_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {  
    Name = "base_vpc_01"
  }
 
}

resource "aws_subnet" "base_subnet_01" {
  vpc_id     = aws_vpc.base_vpc.id
  cidr_block = "10.0.0.0/24" 
  availability_zone = "us-east-1a" 
  tags = {
    Name = "base_subnet_01"
  } 
  # ... More subnet customization
}

# ... Additional subnets as needed

# eks.tf - EKS Cluster Definition
resource "aws_eks_cluster" "base_eks_cluster" {
  name = "base_eks_cluster_01"
  role_arn = aws_iam_role.eks_cluster_role.arn # Reference the role to be created

  # ... EKS Cluster configuration
  

  vpc_config {
    subnet_ids = [aws_subnet.base_subnet_01.id] # Add subnet IDs
  }
  # ... More EKS configuration
}

# iam.tf - IAM Role for EKS and ArgoCD
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks_cluster_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  # ... Necessary permissions for EKS management
}

# argocd.tf - ArgoCD Installation 
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"  # ... ArgoCD Helm chart configuration, including IAM Role integration 
}

# ... Potentially other resources like security groups, etc.
