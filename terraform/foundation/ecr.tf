locals {
  ecr_repositories = toset([
    "api",
    "ingestor-coinbase",
    "ingestor-kraken",
    "normalizer",
    "detector",
    "signal-writer",
  ])
}

resource "aws_ecr_repository" "service" {
  for_each = local.ecr_repositories

  name                 = "${local.name_prefix}/${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${each.key}-ecr"
  })
}
