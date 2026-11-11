# Creates the GitHub OIDC provider and two roles for one repository:
#   my-app-deploy  push to main          -> deploys
#   my-app-plan    pull requests (opt-in) -> read-only, e.g. for terraform plan

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region for the provider. IAM is global, the region only matters for the API endpoint."
  type        = string
  default     = "eu-central-1"
}

module "github_oidc" {
  source = "../.."

  roles = {
    my-app-deploy = {
      description = "Deploys my-org/my-app from the main branch"
      subjects = [{
        repository = "my-org/my-app"
        branches   = ["main"]
      }]
      inline_policies = {
        artifacts = jsonencode({
          Version = "2012-10-17"
          Statement = [{
            Effect   = "Allow"
            Action   = ["s3:PutObject", "s3:GetObject"]
            Resource = ["arn:aws:s3:::my-app-artifacts/*"]
          }]
        })
      }
    }

    my-app-plan = {
      description = "Read-only access for pull request checks in my-org/my-app"
      subjects = [{
        repository   = "my-org/my-app"
        pull_request = true
      }]
      managed_policy_arns = {
        read-only = "arn:aws:iam::aws:policy/ReadOnlyAccess"
      }
    }
  }

  tags = {
    ManagedBy = "terraform"
  }
}

output "oidc_provider_arn" {
  description = "ARN of the created GitHub OIDC provider."
  value       = module.github_oidc.oidc_provider_arn
}

output "role_arns" {
  description = "Use these as role-to-assume in the workflow."
  value       = module.github_oidc.role_arns
}

output "trust_policies" {
  description = "Rendered trust policies, for review."
  value       = module.github_oidc.trust_policies
}
