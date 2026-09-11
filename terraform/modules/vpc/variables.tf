variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ, matching docs/cidr-plan.md"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets, one per AZ, matching docs/cidr-plan.md"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "nat_gateway_az_index" {
  description = "Index into the public subnets list where the single NAT gateway is placed (single-NAT cost trade-off — see docs/build-log.md decision #11)"
  type        = number
  default     = 0
}
