output "vpc_id" {
  description = "The ID of our VPC — useful for debugging in AWS console"
  value       = aws_vpc.main.id
}
output "public_subnet_ids" {
  description = "IDs of the 2 public subnets (where ALB and NAT Gateway live)"
  value       = aws_subnet.public[*].id
}
output "private_subnet_ids" {
  description = "IDs of the 2 private subnets (where EKS nodes live)"
  value       = aws_subnet.private[*].id
}
output "eks_cluster_name" {
  description = "The name of our EKS cluster"
  value       = aws_eks_cluster.main.name
}
output "eks_cluster_endpoint" {
  description = "The URL of the Kubernetes API server (where kubectl sends commands)"
  value       = aws_eks_cluster.main.endpoint
}
output "oidc_provider_arn" {
  description = "ARN of the OIDC provider — needed when setting up ALB Ingress Controller"
  value       = aws_iam_openid_connect_provider.eks.arn
}
output "ecr_frontend_url" {
  description = "URL to push your frontend Docker image to"
  value       = aws_ecr_repository.frontend.repository_url
}
output "ecr_backend_url" {
  description = "URL to push your backend Docker image to"
  value       = aws_ecr_repository.backend.repository_url
}
output "aws_account_id" {
  description = "Your AWS account ID — needed for ECR login commands"
  value       = data.aws_caller_identity.current.account_id
}
output "configure_kubectl" {
  description = "Run this command to connect kubectl to your cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}
