# Runs both examples against the mocked provider and checks the guarantees their
# READMEs promise.

mock_provider "aws" {
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
    }
  }
}

run "basic_example" {
  module {
    source = "./examples/basic"
  }

  assert {
    condition     = output.oidc_provider_arn == "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
    error_message = "The basic example creates the provider."
  }

  assert {
    condition = jsondecode(output.trust_policies["my-app-deploy"]).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == [
      "repo:my-org/my-app:ref:refs/heads/main",
    ]
    error_message = "The deploy role trusts pushes to main only."
  }

  assert {
    condition = jsondecode(output.trust_policies["my-app-plan"]).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == [
      "repo:my-org/my-app:pull_request",
    ]
    error_message = "The plan role is the only one that trusts pull requests."
  }
}

run "multi_environment_example" {
  command = plan

  module {
    source = "./examples/multi-environment"
  }

  assert {
    condition = jsondecode(output.trust_policies["prod"]).Statement == [{
      Sid       = "GitHubActionsExactSubjects"
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = ["repo:my-org/my-app:environment:production:ref:refs/heads/main"]
        }
      }
    }]
    error_message = "prod must be assumable only from main with the production environment, by exact match."
  }

  assert {
    condition = jsondecode(output.trust_policies["qa"]).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == [
      "repo:my-org/my-app:environment:qa:ref:refs/heads/main",
    ]
    error_message = "qa deploys come from main through the qa environment."
  }

  assert {
    condition = jsondecode(output.trust_policies["dev"]).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == [
      "repo:my-org/my-app:environment:dev:ref:refs/heads/*",
    ]
    error_message = "dev accepts any branch, and only via StringLike."
  }

  assert {
    condition     = module.github_oidc.oidc_provider_arn == "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
    error_message = "The example reuses the existing provider."
  }
}
