resource "aws_vpc" "drp_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "VPC-DRP-Grup5" }
}

resource "aws_internet_gateway" "drp_igw" {
  vpc_id = aws_vpc.drp_vpc.id
  tags = { Name = "IGW-DRP" }
}

resource "aws_subnet" "drp_subnet" {
  vpc_id                  = aws_vpc.drp_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = { Name = "Subnet-Publica-DRP" }
}

resource "aws_route_table" "drp_rt" {
  vpc_id = aws_vpc.drp_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.drp_igw.id
  }
}

resource "aws_route_table_association" "drp_rta" {
  subnet_id      = aws_subnet.drp_subnet.id
  route_table_id = aws_route_table.drp_rt.id
}

resource "aws_eip_association" "drp_eip_assoc" {
  instance_id   = aws_instance.drp_server.id
  allocation_id = "eipalloc-020e8f22efa569e25"
}
