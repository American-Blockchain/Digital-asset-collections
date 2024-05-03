provider "aws" {
  region = local.region
}

#ocals {
#  name = "lab-work"
#}
################################################################################
# Cluster Authentication / Authorization
################################################################################
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}
###
###provider "kubectl" {
###  apply_retry_count      = 5
###  host                   = module.eks.cluster_endpoint
###  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
###  load_config_file       = false
###
###  exec {
###    api_version = "client.authentication.k8s.io/v1beta1"
###    command     = "aws"
###    # This requires the awscli to be installed locally where Terraform is executed
###    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
###  }
###}

#---------------------------------------------------------------
# Data sources to get VPC, subnets, AZs, etc
#---------------------------------------------------------------
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

locals {
  name   = basename(path.cwd)
  region = "us-east-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

################################################################################
# Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8.5"

  cluster_name                    = local.name
  cluster_version                 = "1.29"
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true


  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    initial = {
      node_group_names = "lab-workers"
      instance_types   = ["m5.large"]
      min_size         = 1
      max_size         = 5
      desired_size     = 3
      subnet_ids       = module.vpc.private_subnets
    }
  }

  tags = local.tags
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.16.2" #ensure to update this to the latest/desired version

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn
  #cluster_id        = module.eks.cluster_id

  # EKS Addons
eks_addons = {
  # Core Kubernetes addons
  coredns    = true 
  kube-proxy = true
  vpc-cni    = true

  # Storage addons
  aws-ebs-csi-driver = true

  # Load balancing addon
  #enable_aws_load_balancer_controller = true

  # Autoscaling addons
  #enable_cluster_proportional_autoscaler = true
  #enable_karpenter                       = true

  # Monitoring and logging addons
  #enable_kube_prometheus_stack = true
  #enable_metrics_server        = true

  # DNS management addon
  #enable_external_dns = true

  # Certificate management addon
  #enable_cert_manager = true
}
    
    cert_manager_route53_hosted_zone_arns = ["arn:aws:route53:::hostedzone/Z09776921VS6Z2AFA0F0W"]

    tags = {
      Environment = "dev"
    }
  }


################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8.1"

  manage_default_vpc = true

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]

  enable_nat_gateway = false


  # private_subnet_tags = {
  # "kubernetes.io/role/internal-elb"             = 1
  #"kubernetes.io/cluster/${local.cluster_name}" = "shared"

  # }
  # public_subnet_tags = {
  #"kubernetes.io/cluster/${local.cluster_name}" = "shared"
  #  "kubernetes.io/role/elb"                      = 1
  # }

  tags = local.tags
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 5.1"

  vpc_id = module.vpc.vpc_id

  # Security group
  create_security_group      = true
  security_group_name_prefix = "${local.name}-vpc-endpoints-"
  security_group_description = "VPC endpoint security group"
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from VPC"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  endpoints = merge({
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags = {
        Name = "${local.name}-s3"
      }
    }
    },
    { for service in toset(["autoscaling", "ecr.api", "ecr.dkr", "ec2", "ec2messages", "elasticloadbalancing", "sts", "kms", "logs", "ssm", "ssmmessages"]) :
      replace(service, ".", "_") =>
      {
        service             = service
        subnet_ids          = module.vpc.private_subnets
        private_dns_enabled = true
        tags                = { Name = "${local.name}-${service}" }
      }
  })

  tags = local.tags
}