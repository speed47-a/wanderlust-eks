variable "aws_region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-east-1" 
}
variable "project_name" {
  description = "Project name — used as a prefix for all resource names"
  type        = string
  default     = "wanderlust"
}
variable "vpc_cidr" {
  description = "IP range for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
variable "public_subnet_cidrs" {
  description = "IP ranges for public subnets (one per availability zone)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}
variable "private_subnet_cidrs" {
  description = "IP ranges for private subnets (one per availability zone)"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}
variable "availability_zones" {
  description = "Availability zones to spread resources across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}
variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.30"
}
variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.small"
}
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
variable "node_disk_size" {
  description = "Disk size in GB for each worker node"
  type        = number
  default     = 20
}
