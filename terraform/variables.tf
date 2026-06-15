# ============================================================
# variables.tf
# This file defines all the INPUTS our Terraform code accepts.
#
# Think of variables like function parameters in programming:
#   - variables.tf  = defines what parameters exist
#   - terraform.tfvars = provides the actual values
#
# Why do this instead of hardcoding values?
# So we can reuse the same code for different environments
# (dev, staging, prod) by just changing the .tfvars file.
# ============================================================


# The AWS region where everything will be created
variable "aws_region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-east-1" # US East (N. Virginia) — cheapest region
}


# A name prefix used for ALL resources (so you can find them easily in AWS console)
# Example: "wanderlust-vpc", "wanderlust-eks-cluster", "wanderlust-nodes"
variable "project_name" {
  description = "Project name — used as a prefix for all resource names"
  type        = string
  default     = "wanderlust"
}


# The IP address range for our entire private network (VPC)
# 10.0.0.0/16 gives us 65,536 IP addresses to work with
# We'll split these into smaller subnets below
variable "vpc_cidr" {
  description = "IP range for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}


# IP ranges for the 2 PUBLIC subnets
# Public = reachable from the internet (Load Balancer goes here)
# /24 = 256 IP addresses each
variable "public_subnet_cidrs" {
  description = "IP ranges for public subnets (one per availability zone)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}


# IP ranges for the 2 PRIVATE subnets
# Private = NOT reachable from internet (EKS worker nodes go here)
variable "private_subnet_cidrs" {
  description = "IP ranges for private subnets (one per availability zone)"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}


# Availability Zones = separate physical data centers within a region
# Using 2 AZs means if one data center has issues, the other keeps running
variable "availability_zones" {
  description = "Availability zones to spread resources across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}


# Which version of Kubernetes to run
# Always use a recent stable version (not the absolute latest)
variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.30"
}


# The EC2 instance type for worker nodes
# t3.medium = 2 vCPU, 4GB RAM — minimum practical size for running K8s pods
# t2.micro (free tier) is too small — Kubernetes itself uses ~1.5GB RAM
variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.small"
}


# How many worker nodes to run
# desired = how many to run normally
# min     = never go below this (even under low load)
# max     = never go above this (even under high load)
variable "node_desired_size" {
  description = "Number of worker nodes to run normally"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes (for auto-scaling)"
  type        = number
  default     = 3
}


# Storage size for each worker node's disk
# 20GB is enough for the OS + Docker images
variable "node_disk_size" {
  description = "Disk size in GB for each worker node"
  type        = number
  default     = 20
}
