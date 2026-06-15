# ============================================================
# terraform.tfvars
# This file provides the ACTUAL VALUES for our variables.
#
# These values override the "default" values in variables.tf
# You can change any of these to customize the deployment.
#
# ⚠️  DO NOT commit this file to a public GitHub repo if it
#     ever contains secrets (passwords, API keys, etc.)
#     This file is safe to commit since it has no secrets.
# ============================================================

# AWS region — us-east-1 is cheapest
aws_region   = "us-east-1"

# Name used as prefix for all resources
project_name = "wanderlust"

# Network configuration
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]
availability_zones   = ["us-east-1a", "us-east-1b"]

# Kubernetes version
eks_cluster_version = "1.30"

# Worker node configuration
# t3.medium = 2 vCPU, 4GB RAM — minimum for running K8s workloads
node_instance_type = "t3.small"
node_desired_size  = 2
node_min_size      = 2
node_max_size      = 3
node_disk_size     = 20
