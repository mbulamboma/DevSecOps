# Discovers the public/private subnet split of an existing VPC.
# A subnet is "public" if its route table has a 0.0.0.0/0 route to an IGW.

variable "vpc_id" {
  description = "Existing VPC ID to inspect"
  type        = string
}

data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

data "aws_subnet" "by_id" {
  for_each = toset(data.aws_subnets.all.ids)
  id       = each.value
}

data "aws_route_table" "by_subnet" {
  for_each  = toset(data.aws_subnets.all.ids)
  subnet_id = each.value
}

locals {
  public_subnet_ids = [
    for sid, rt in data.aws_route_table.by_subnet :
    sid if anytrue([
      for r in rt.routes : try(startswith(r.gateway_id, "igw-"), false)
    ])
  ]

  private_subnet_ids = [
    for sid in data.aws_subnets.all.ids :
    sid if !contains(local.public_subnet_ids, sid)
  ]

  # One public subnet per AZ (lowest ID = deterministic)
  public_per_az = {
    for az in distinct([
      for s in data.aws_subnet.by_id : s.availability_zone
      if contains(local.public_subnet_ids, s.id)
    ]) :
    az => sort([
      for s in data.aws_subnet.by_id : s.id
      if s.availability_zone == az && contains(local.public_subnet_ids, s.id)
    ])[0]
  }

  private_per_az = {
    for az in distinct([
      for s in data.aws_subnet.by_id : s.availability_zone
      if contains(local.private_subnet_ids, s.id)
    ]) :
    az => sort([
      for s in data.aws_subnet.by_id : s.id
      if s.availability_zone == az && contains(local.private_subnet_ids, s.id)
    ])[0]
  }

  any_per_az = {
    for az in distinct([for s in data.aws_subnet.by_id : s.availability_zone]) :
    az => sort([for s in data.aws_subnet.by_id : s.id if s.availability_zone == az])[0]
  }
}

output "vpc_id" { value = var.vpc_id }
output "public_subnet_ids" { value = values(local.public_per_az) }
output "private_subnet_ids" {
  value = length(local.private_per_az) >= 2 ? values(local.private_per_az) : values(local.any_per_az)
}
