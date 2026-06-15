# ============================================================
# eks.tf
# This file creates:
#   1. IAM Role for the EKS control plane
#   2. The EKS cluster itself
#   3. IAM Role for the worker nodes
#   4. The worker node group (EC2 instances)
#   5. OIDC Provider (so pods can talk to AWS securely)
#   6. ECR repositories (to store our Docker images)
#
# What is IAM?
# IAM = Identity and Access Management
# In AWS, every service that needs to DO something (like create
# a load balancer or pull a Docker image) needs PERMISSION first.
# We grant permissions using IAM Roles.
# ============================================================


# ── PART 1: IAM Role for the EKS Control Plane ──────────────
#
# The EKS control plane (the Kubernetes API server, scheduler, etc.)
# needs AWS permissions to do things like:
#   - Create/manage network interfaces for pods
#   - Update security groups
#   - Write logs to CloudWatch
#
# Step 1a: Create the role and define WHO can use it
resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"

  # "assume_role_policy" defines WHO is allowed to USE this role.
  # Here we say: "the EKS service (eks.amazonaws.com) can use this role"
  # This is called a "trust policy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

# Step 1b: Attach the official AWS-managed EKS policy to the role
# This policy contains all the permissions EKS needs to manage the cluster
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


# ── PART 2: The EKS Cluster ──────────────────────────────────
#
# This creates the Kubernetes control plane.
# The control plane includes:
#   - API Server     → receives kubectl commands
#   - etcd           → stores all cluster state (like a database)
#   - Scheduler      → decides which node to run each pod on
#   - Controller     → makes sure desired state matches actual state
#
# AWS manages all of this for you. You just pay $0.10/hr.
# You never SSH into the control plane — AWS handles it.

resource "aws_eks_cluster" "main" {
  name     = var.project_name          # cluster will be named "wanderlust"
  version  = var.eks_cluster_version   # Kubernetes 1.30
  role_arn = aws_iam_role.eks_cluster.arn  # give it the IAM role we created above

  vpc_config {
    # Put the cluster in ALL our subnets (public + private)
    # EKS needs to know about all subnets so it can place things correctly
    subnet_ids = concat(
      aws_subnet.public[*].id,   # [public-subnet-1-id, public-subnet-2-id]
      aws_subnet.private[*].id   # [private-subnet-1-id, private-subnet-2-id]
    )

    # endpoint_private_access = true  → your nodes can talk to the API server privately
    # endpoint_public_access  = true  → YOU can run kubectl from your laptop
    # In production you'd set public_access = false for security
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # Send control plane logs to CloudWatch for debugging
  # (costs a tiny bit but very helpful when things go wrong)
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  # Make sure IAM role + policy are ready before creating the cluster
  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]

  tags = {
    Name = var.project_name
  }
}


# ── PART 3: IAM Role for Worker Nodes ───────────────────────
#
# The EC2 instances that run our pods also need AWS permissions:
#   - Join the EKS cluster
#   - Pull Docker images from ECR
#   - Manage their own network interfaces (for pod networking)
#
# Step 3a: Create the role — this time EC2 can use it (not EKS)
resource "aws_iam_role" "eks_nodes" {
  name = "${var.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }  # EC2 instances can use this role
    }]
  })
}

# Step 3b: Attach the 3 policies nodes need

# Policy 1: Lets the node register with and communicate with the EKS cluster
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Policy 2: Lets the node manage pod networking (IP addresses for pods)
# CNI = Container Network Interface — the plugin that gives each pod an IP
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Policy 3: Lets the node PULL Docker images from ECR (read-only)
resource "aws_iam_role_policy_attachment" "eks_ecr_readonly" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}


# ── PART 4: EKS Node Group ───────────────────────────────────
#
# This creates the actual EC2 machines that run your pods.
# A "managed node group" means AWS handles:
#   - Launching the EC2 instances
#   - Installing Kubernetes on them
#   - Joining them to the cluster
#   - Patching/updating them
# You just define how many and what size.

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name       # attach to our cluster
  node_group_name = "${var.project_name}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn      # use the node IAM role

  # Place nodes in PRIVATE subnets (not public)
  # Nodes don't need to be directly reachable from internet
  # Traffic reaches them via the Load Balancer → private subnet
  subnet_ids = aws_subnet.private[*].id

  instance_types = [var.node_instance_type]  # t3.medium
  disk_size      = var.node_disk_size        # 20GB

  # SPOT = up to 70% cheaper than ON_DEMAND
  # AWS can reclaim spot instances with 2 min notice
  # Fine for learning projects, avoid for production
  capacity_type = "ON_DEMAND"

  # Auto-scaling configuration:
  # Kubernetes will automatically add/remove nodes based on pod demand
  scaling_config {
    desired_size = var.node_desired_size  # start with 2 nodes
    min_size     = var.node_min_size      # never go below 2
    max_size     = var.node_max_size      # never go above 3
  }

  # When updating nodes, replace them one at a time
  # (so your app stays running during updates)
  update_config {
    max_unavailable = 1
  }

  # Wait for all IAM policies to be attached before creating nodes
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_readonly,
  ]

  tags = {
    Name = "${var.project_name}-node-group"
  }
}


# ── PART 5: OIDC Provider ────────────────────────────────────
#
# This is the most complex part — but very important for security.
#
# PROBLEM: Some pods need to make AWS API calls.
# For example, the ALB Ingress Controller pod needs to create
# Load Balancers in AWS. How does it authenticate with AWS?
#
# BAD solution: hardcode AWS credentials in the pod → security nightmare
#
# GOOD solution: IRSA (IAM Roles for Service Accounts)
# OIDC makes this possible. It creates a trust link between
# your Kubernetes cluster and AWS IAM, so pods can securely
# get temporary AWS credentials without any hardcoded secrets.
#
# Think of it like: "I trust this Kubernetes cluster to vouch
# for its pods' identities when they request AWS access"

# Step 5a: Get the security certificate from the EKS OIDC endpoint
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# Step 5b: Register our EKS cluster as a trusted identity provider in AWS IAM
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}


# ── PART 6: ECR Repositories ─────────────────────────────────
#
# ECR = Elastic Container Registry
# Like DockerHub but private and inside AWS.
# Free for first 50GB/month. Our lifecycle policy keeps it well under that.
#
# We need 2 repos: one for frontend, one for backend

resource "aws_ecr_repository" "frontend" {
  name = "${var.project_name}-frontend"  # wanderlust-frontend

  # MUTABLE = you can overwrite tags (e.g. push a new "latest" image)
  # IMMUTABLE = once pushed, a tag can never be overwritten (safer for prod)
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true  # free vulnerability scan every time you push an image
  }
}

resource "aws_ecr_repository" "backend" {
  name                 = "${var.project_name}-backend"  # wanderlust-backend
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Lifecycle policy: automatically delete old images
# We only keep the 5 most recent images per repo
# This prevents storage costs from growing over time
resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last 5 images, delete the rest"
      selection = {
        tagStatus   = "any"               # applies to all images regardless of tag
        countType   = "imageCountMoreThan"
        countNumber = 5                   # if more than 5 images exist...
      }
      action = { type = "expire" }        # ...delete the oldest ones
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last 5 images, delete the rest"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
