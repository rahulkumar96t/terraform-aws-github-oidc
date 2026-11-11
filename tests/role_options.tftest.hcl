# Per-role IAM options: name, path, session length, boundary, tags, policies.

mock_provider "aws" {
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
    }
  }
}

run "defaults_are_conservative" {
  variables {
    roles = {
      deploy = { subjects = [{ repository = "my-org/my-app", branches = ["main"] }] }
    }
  }

  assert {
    condition     = aws_iam_role.this["deploy"].name == "deploy" && aws_iam_role.this["deploy"].path == "/"
    error_message = "The role name defaults to the map key and the path to /."
  }

  assert {
    condition     = aws_iam_role.this["deploy"].max_session_duration == 3600
    error_message = "Sessions default to one hour."
  }

  assert {
    condition     = aws_iam_role.this["deploy"].permissions_boundary == null
    error_message = "No permissions boundary unless one is configured."
  }

  assert {
    condition     = aws_iam_role.this["deploy"].force_detach_policies
    error_message = "Roles must be destroyable while policies are still attached."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.managed) == 0 && length(aws_iam_role_policy.inline) == 0
    error_message = "No policies are attached unless configured."
  }
}

run "boundary_session_path_and_tags" {
  variables {
    tags = { ManagedBy = "terraform", Team = "platform" }
    roles = {
      prod = {
        name                 = "gha-my-app-prod"
        path                 = "/github-actions/"
        description          = "Deploys my-app to production"
        max_session_duration = 7200
        permissions_boundary = "arn:aws:iam::111111111111:policy/deploy-boundary"
        tags                 = { Team = "my-app", Environment = "prod" }
        subjects             = [{ repository = "my-org/my-app", environments = ["production"] }]
      }
    }
  }

  assert {
    condition     = aws_iam_role.this["prod"].permissions_boundary == "arn:aws:iam::111111111111:policy/deploy-boundary"
    error_message = "The permissions boundary must be set on the role."
  }

  assert {
    condition     = aws_iam_role.this["prod"].max_session_duration == 7200
    error_message = "max_session_duration must be passed through."
  }

  assert {
    condition     = aws_iam_role.this["prod"].name == "gha-my-app-prod" && aws_iam_role.this["prod"].path == "/github-actions/"
    error_message = "Explicit name and path must be used."
  }

  assert {
    condition     = aws_iam_role.this["prod"].description == "Deploys my-app to production"
    error_message = "The description must be passed through."
  }

  assert {
    condition     = aws_iam_role.this["prod"].tags == tomap({ ManagedBy = "terraform", Team = "my-app", Environment = "prod" })
    error_message = "Role tags must be merged over module tags."
  }

  assert {
    condition     = output.role_names["prod"] == "gha-my-app-prod"
    error_message = "role_names must report the real role name."
  }
}

run "managed_and_inline_policies" {
  variables {
    roles = {
      deploy = {
        subjects = [{ repository = "my-org/my-app", branches = ["main"] }]
        managed_policy_arns = {
          ecr = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
          app = "arn:aws:iam::111111111111:policy/my-app-deploy"
        }
        inline_policies = {
          assets = jsonencode({
            Version   = "2012-10-17"
            Statement = [{ Effect = "Allow", Action = ["s3:PutObject"], Resource = ["arn:aws:s3:::my-app-assets/*"] }]
          })
        }
      }
    }
  }

  assert {
    condition     = toset(keys(aws_iam_role_policy_attachment.managed)) == toset(["deploy/ecr", "deploy/app"])
    error_message = "Attachments must be keyed by role and label, not by ARN."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.managed["deploy/app"].policy_arn == "arn:aws:iam::111111111111:policy/my-app-deploy"
    error_message = "The labelled ARN must be attached."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.managed["deploy/ecr"].role == "deploy"
    error_message = "Attachments must target the role by name."
  }

  assert {
    condition     = aws_iam_role_policy.inline["deploy/assets"].name == "assets" && aws_iam_role_policy.inline["deploy/assets"].role == "deploy"
    error_message = "Inline policies must keep their name and target the role."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.inline["deploy/assets"].policy).Statement[0].Action == ["s3:PutObject"]
    error_message = "The inline document must be passed through unchanged."
  }
}

run "warns_when_trust_policy_exceeds_default_quota" {
  command = plan

  variables {
    create_oidc_provider = false
    oidc_provider_arn    = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
    roles = {
      many-branches = {
        subjects = [{
          repository = "my-org/my-app"
          branches   = [for i in range(60) : "release/2026-${i}"]
        }]
      }
    }
  }

  expect_failures = [check.trust_policy_size]

  assert {
    condition     = length(output.trust_policies["many-branches"]) > 2048
    error_message = "The test input must actually exceed the default quota."
  }
}
