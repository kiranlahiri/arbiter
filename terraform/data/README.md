# Terraform Data

This phase provisions the PostgreSQL data layer for Arbiter.

## Current Scope

Right now this phase includes only:

- PostgreSQL security group
- DB subnet group
- one RDS PostgreSQL instance
- outputs for the DB endpoint and related IDs

## Relationship To Foundation

This layer depends on values from `terraform/foundation`.

For now, pass them explicitly through `terraform.tfvars`:

- `vpc_id`
- `private_subnet_ids`
- `app_internal_security_group_id`

That keeps the dependency visible while the project is still small.

## Suggested Workflow

1. Copy the example vars file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

2. Fill in the foundation outputs and set a real `db_password`.

3. Run:

```bash
terraform init
terraform plan
```

## Notes

- The DB is private-only.
- The DB is reachable only from the internal app security group.
- This uses a simple single-instance RDS shape suitable for `dev`.
