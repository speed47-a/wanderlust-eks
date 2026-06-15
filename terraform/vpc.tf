# ============================================================
# vpc.tf
# This file builds our entire network from scratch.
#
# What we're building:
#
#           INTERNET
#               │
#       Internet Gateway        ← front door to the internet
#               │
#         VPC (10.0.0.0/16)    ← our private network
#         │              │
#   Public Subnets   Private Subnets
#   (ALB lives here) (EKS nodes live here)
#         │
#     NAT Gateway              ← lets private nodes reach internet
#                                 but blocks internet from reaching them
#
# ============================================================


# ── STEP 1: Create the VPC (our private network) ────────────

resource "aws_vpc" "main" {

  # The IP address range for our entire network
  # 10.0.0.0/16 = 65,536 available IP addresses
  cidr_block = var.vpc_cidr

  # These two settings allow DNS to work inside the VPC.
  # Without them, pods can't resolve service names like
  # "my-service.default.svc.cluster.local"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}


# ── STEP 2: Create 2 Public Subnets ─────────────────────────
# Public subnets are for resources that need to be reachable from the internet.
# In our case: the Application Load Balancer (ALB) and NAT Gateway.

resource "aws_subnet" "public" {
  # count = 2, so Terraform runs this block twice
  # First run:  count.index = 0 → 10.0.1.0/24 in us-east-1a
  # Second run: count.index = 1 → 10.0.2.0/24 in us-east-1b
  count = length(var.public_subnet_cidrs)

  vpc_id            = aws_vpc.main.id                          # put this subnet inside our VPC
  cidr_block        = var.public_subnet_cidrs[count.index]     # 10.0.1.0/24 or 10.0.2.0/24
  availability_zone = var.availability_zones[count.index]      # us-east-1a or us-east-1b

  # Any EC2 launched in this subnet automatically gets a public IP
  # This is what makes a subnet "public" — instances are reachable from internet
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${count.index + 1}"

    # This tag is REQUIRED for the AWS Load Balancer Controller
    # It tells AWS: "create internet-facing load balancers in these subnets"
    # Without this tag, your Kubernetes Ingress will never get an ALB
    "kubernetes.io/role/elb" = "1"

    # Tells EKS this subnet belongs to our cluster
    "kubernetes.io/cluster/${var.project_name}" = "shared"
  }
}


# ── STEP 3: Create 2 Private Subnets ────────────────────────
# Private subnets are for resources that should NOT be directly
# reachable from the internet. Our EKS worker nodes live here.
# They can still reach the internet (via NAT), but internet
# cannot reach them directly — much more secure.

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]    # 10.0.3.0/24 or 10.0.4.0/24
  availability_zone = var.availability_zones[count.index]

  # Notice: NO map_public_ip_on_launch here
  # Instances in private subnets get NO public IP → not reachable from internet

  tags = {
    Name = "${var.project_name}-private-${count.index + 1}"

    # For internal load balancers (service-to-service traffic inside the cluster)
    "kubernetes.io/role/internal-elb" = "1"

    "kubernetes.io/cluster/${var.project_name}" = "shared"
  }
}


# ── STEP 4: Internet Gateway ─────────────────────────────────
# The IGW is the "front door" between your VPC and the internet.
# Without it: nothing in your VPC can reach the internet at all.
# One IGW per VPC — no sizing needed, just attach it.

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}


# ── STEP 5: Elastic IP for NAT Gateway ──────────────────────
# A static, permanent public IP address.
# The NAT Gateway needs this so it has a fixed IP to represent
# all outbound traffic from our private subnets.

resource "aws_eip" "nat" {
  domain = "vpc" # "vpc" means this IP belongs to our VPC

  tags = {
    Name = "${var.project_name}-nat-eip"
  }

  # Make sure the IGW exists before creating this
  # (EIP needs the IGW to be attached first)
  depends_on = [aws_internet_gateway.main]
}


# ── STEP 6: NAT Gateway ──────────────────────────────────────
# The NAT Gateway is a "one-way valve":
#   ✅ Private subnet → NAT → Internet  (outbound allowed)
#   ❌ Internet → NAT → Private subnet  (inbound blocked)
#
# Example use: EKS node in private subnet pulling a Docker image from ECR
#
# Important: NAT Gateway must live in a PUBLIC subnet
# (it needs internet access itself to forward traffic)
# Cost: ~$32/month — destroy when not using!

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id           # use our static IP
  subnet_id     = aws_subnet.public[0].id  # place it in the first public subnet

  tags = {
    Name = "${var.project_name}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}


# ── STEP 7: Route Tables ─────────────────────────────────────
# Route tables are like GPS for network traffic.
# They say: "if traffic is going to X, send it via Y"
#
# We need 2 route tables:
#   1. Public  → send internet traffic via IGW
#   2. Private → send internet traffic via NAT Gateway

# -- Public Route Table --
# Rule: "Any traffic going to the internet (0.0.0.0/0) → use the IGW"
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"                    # 0.0.0.0/0 = "any destination on the internet"
    gateway_id = aws_internet_gateway.main.id    # send it through the IGW
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Associate the public route table with BOTH public subnets
# (without this association, the route table has no effect)
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)     # do this for each public subnet
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}


# -- Private Route Table --
# Rule: "Any traffic going to the internet → use the NAT Gateway"
# The NAT Gateway then forwards it to the IGW on the node's behalf
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id    # send it through NAT (not IGW directly)
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

# Associate the private route table with BOTH private subnets
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
