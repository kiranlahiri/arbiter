# Terraform Messaging

This phase provisions the messaging infrastructure for Arbiter.

Its goal is to stay small and understandable while we decide how much hosted Kafka complexity is justified.

## Current Scope

Right now this phase includes only:

- Terraform version constraints
- AWS provider configuration
- messaging-layer input variables
- Kafka security group
- one Kafka EC2 broker
- basic outputs

## Why Start Here

Kafka is the first AWS component where the project can become overbuilt quickly.

Starting with the security and placement inputs first lets us confirm:

- which subnet the broker should live in
- which application workloads should be allowed to reach it
- whether SSH access should exist at all

before we commit to the EC2 instance and bootstrap logic.

## Planned Kafka Shape

The intended first hosted Kafka shape is:

- one EC2 instance
- one Kafka broker
- one `dev` environment
- EBS-backed storage
- internal broker traffic allowed only from Arbiter application workloads
- single-node KRaft mode

For now, the expected direction is:

- place the broker in a public subnet to avoid introducing NAT costs yet
- keep Kafka itself private by security group
- allow inbound `9092` only from internal app workloads
- allow SSH only from explicitly approved CIDRs if needed
- advertise the broker on its private IP so ECS workloads can reach it inside the VPC

## Relationship To Foundation

This layer depends on values from `terraform/foundation`.

For now, pass them explicitly through `terraform.tfvars`:

- `vpc_id`
- `subnet_id`
- `app_internal_security_group_id`

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

## Kafka Bootstrap Notes

- The broker is installed through EC2 user data.
- The bootstrap script installs Java, downloads Apache Kafka, and configures single-node KRaft mode.
- The broker listens on:
  - `9092` for client traffic
  - `9093` for the controller listener

## Next Addition

After the instance is up, the next likely work is:

- validate SSH or system logs if needed
- confirm Kafka is listening on the broker
- create topics on the hosted broker
- pass the broker endpoint into the ECS worker services
