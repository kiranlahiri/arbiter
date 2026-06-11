# Terraform App

This phase provisions the first compute-facing infrastructure for Arbiter.

## Current Scope

Right now this phase includes only:

- ECS cluster
- API service security group
- CloudWatch log group for the API
- public Application Load Balancer
- target group
- listener

This phase does **not** yet define:

- task execution IAM roles
- task definitions
- ECS services
- image push workflow

## Relationship To Foundation

This layer depends on values from `terraform/foundation`.

For now, pass them explicitly through `terraform.tfvars`:

- `vpc_id`
- `public_subnet_ids`
- `public_entry_security_group_id`

## Why Keep It This Small

The goal is to establish the app compute shape without forcing a running ECS deployment before:

- images are pushed to ECR
- IAM roles are ready
- database wiring is finalized

## Suggested Workflow

1. Copy the example vars file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

2. Fill in the foundation outputs.

3. Run:

```bash
terraform init
terraform plan
```
