resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true # off by default on custom VPCs — needed for
                               # EC2 public DNS names (Phase 2 lesson)

  tags = {
    Name = "vpc-project"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true # combined with the IGW route below, this is
                                  # what actually makes a subnet "public" —
                                  # neither condition alone is sufficient

  tags = {
    Name = "public-${substr(var.azs[count.index], -1, 1)}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "private-${substr(var.azs[count.index], -1, 1)}"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "vpc-project-igw"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "vpc-project-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  # Single NAT gateway, not one per AZ — same cost-conscious trade-off as
  # Phase 3, documented in docs/build-log.md decision #11.
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[var.nat_gateway_az_index].id

  tags = {
    Name = "vpc-project-nat"
  }

  depends_on = [aws_internet_gateway.main] # NAT gateways need the IGW to exist
                                            # first, but nothing above references
                                            # it directly — this states the
                                            # dependency Terraform can't infer
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
