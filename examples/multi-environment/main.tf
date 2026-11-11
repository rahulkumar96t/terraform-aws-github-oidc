# dev / qa / prod deploy roles for my-org/my-app, reusing an OIDC provider that
# another stack already created in this account.
#
# The repository uses a customised sub claim so that AWS sees both the GitHub
# environment and the git ref of every job. Configure it on GitHub before the
# first deploy (see the README):
#
#   PUT /repos/my-org/my-app/actions/oidc/customization/sub
#   {"use_default": false, "include_claim_keys": ["repo", "context", "ref"]}
#
# Tokens then carry subjects such as
#   repo:my-org/my-app:environment:production:ref:refs/heads/main
# and the prod trust policy matches exactly that string.

provider "aws" {
  region = var.region
}

locals {
  repository = "my-org/my-app"

  # Least-privilege placeholder: each environment may only write to its own
  # artifact bucket. Replace with what your deployment needs.
  deploy_policy = {
    for env in ["dev", "qa", "prod"] : env => jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = ["arn:aws:s3:::my-app-${env}-artifacts", "arn:aws:s3:::my-app-${env}-artifacts/*"]
      }]
    })
  }
}

module "github_oidc" {
  source = "../.."

  create_oidc_provider = false
  oidc_provider_arn    = var.oidc_provider_arn

  # Matches the repository's include_claim_keys.
  subject_claim_keys = ["repo", "context", "ref"]

  roles = {
    # Any branch may deploy to dev, but only through the "dev" environment.
    dev = {
      name           = "my-app-dev-deploy"
      wildcard_match = true
      subjects = [{
        repository   = local.repository
        environments = ["dev"]
        claims       = { ref = "refs/heads/*" }
      }]
      inline_policies = { deploy = local.deploy_policy["dev"] }
    }

    # QA deploys come from main only.
    qa = {
      name = "my-app-qa-deploy"
      subjects = [{
        repository   = local.repository
        environments = ["qa"]
        claims       = { ref = "refs/heads/main" }
      }]
      inline_policies = { deploy = local.deploy_policy["qa"] }
    }

    # Production: main branch AND the "production" environment, exact match,
    # behind a permissions boundary and with the shortest session.
    prod = {
      name                 = "my-app-prod-deploy"
      max_session_duration = 3600
      permissions_boundary = var.prod_permissions_boundary
      subjects = [{
        repository   = local.repository
        environments = ["production"]
        claims       = { ref = "refs/heads/main" }
      }]
      inline_policies = { deploy = local.deploy_policy["prod"] }
      tags            = { Environment = "prod" }
    }
  }

  tags = {
    ManagedBy   = "terraform"
    Application = "my-app"
  }
}
