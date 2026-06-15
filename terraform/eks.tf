resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
resource "aws_eks_cluster" "main" {
  name     = var.project_name          
  version  = var.eks_cluster_version   
  role_arn = aws_iam_role.eks_cluster.arn  
  vpc_config {
    subnet_ids = concat(
      aws_subnet.public[*].id,   
      aws_subnet.private[*].id   
    )
    endpoint_private_access = true
    endpoint_public_access  = true
  }
  enabled_cluster_log_types = ["api", "audit", "authenticator"]
  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
  tags = {
    Name = var.project_name
  }
}
resource "aws_iam_role" "eks_nodes" {
  name = "${var.project_name}-eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }  
    }]
  })
}
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
resource "aws_iam_role_policy_attachment" "eks_ecr_readonly" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name       
  node_group_name = "${var.project_name}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn      
  subnet_ids = aws_subnet.private[*].id
  instance_types = [var.node_instance_type]  
  disk_size      = var.node_disk_size        
  capacity_type = "ON_DEMAND"
  scaling_config {
    desired_size = var.node_desired_size  
    min_size     = var.node_min_size      
    max_size     = var.node_max_size      
  }
  update_config {
    max_unavailable = 1
  }
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_readonly,
  ]
  tags = {
    Name = "${var.project_name}-node-group"
  }
}
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
resource "aws_ecr_repository" "frontend" {
  name = "${var.project_name}-frontend"  
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true  
  }
}
resource "aws_ecr_repository" "backend" {
  name                 = "${var.project_name}-backend"  
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}
resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name
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
  resource "aws_security_group_rule" "eks_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = <your_eks_node_sg_id>
}
resource "aws_security_group_rule" "eks_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = <your_eks_node_sg_id>
}
}
