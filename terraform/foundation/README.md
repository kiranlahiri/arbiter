# Terraform Foundation

This is the first Terraform phase for Arbiter.

Its job is to stay intentionally small and understandable.

## Current Scope

Right now this phase includes only:

- Terraform version constraints
- AWS provider configuration
- naming and CIDR variables
- one VPC
- public and private subnets
- internet gateway
- public and private route tables
- basic security groups
- basic outputs

## Why Start Here

The goal is to build the AWS environment in small, explainable layers.

We are not trying to define the full infrastructure all at once.

This version intentionally does not include a NAT gateway yet.

That keeps the `dev` foundation cheaper while we are still learning and iterating.

Implication:

- public subnets have outbound internet access
- private subnets are internal-only for now

The next additions to this foundation phase will likely be:

- optional NAT gateway later if private workloads need outbound internet access
- ECR or more workload-specific security groups later

## Suggested Workflow

From this directory:

```bash
terraform init
terraform plan
```

If you want to target a different region:

```bash
terraform plan -var="aws_region=us-east-2"
```
