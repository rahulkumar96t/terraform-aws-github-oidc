# Creating the OIDC provider versus reusing an existing one.

mock_provider "aws" {
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
    }
  }
}

variables {
  roles = {
    deploy = {
      subjects = [{ repository = "my-org/my-app", branches = ["main"] }]
    }
  }
}

run "creates_provider_by_default" {
  variables {
    tags = { Team = "platform" }
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 1
    error_message = "The provider must be created when no ARN is passed."
  }

  assert {
    condition     = aws_iam_openid_connect_provider.github[0].url == "https://token.actions.githubusercontent.com"
    error_message = "The provider must use GitHub's issuer URL."
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github[0].client_id_list) == 1 && contains(aws_iam_openid_connect_provider.github[0].client_id_list, "sts.amazonaws.com")
    error_message = "The provider must register sts.amazonaws.com as its only audience."
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github[0].thumbprint_list) == 0
    error_message = "No thumbprints are configured unless thumbprint_list is set."
  }

  assert {
    condition     = aws_iam_openid_connect_provider.github[0].tags == tomap({ Team = "platform" })
    error_message = "Module tags must be applied to the provider."
  }

  assert {
    condition     = output.oidc_provider_arn == aws_iam_openid_connect_provider.github[0].arn
    error_message = "The output must expose the created provider."
  }

  assert {
    condition     = jsondecode(output.trust_policies["deploy"]).Statement[0].Principal.Federated == aws_iam_openid_connect_provider.github[0].arn
    error_message = "Roles must trust the created provider."
  }
}

run "provider_only_bootstrap" {
  # A bootstrap stack can create just the provider and leave roles to others.
  variables {
    roles = {}
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 1 && length(aws_iam_role.this) == 0
    error_message = "With no roles only the provider is created."
  }

  assert {
    condition     = output.role_arns == {} && output.trust_policies == {}
    error_message = "Role outputs must be empty maps, not null."
  }
}

run "reuses_existing_provider" {
  # Everything is known at plan time when the provider ARN is passed in.
  command = plan

  variables {
    create_oidc_provider = false
    oidc_provider_arn    = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "No provider may be created when an existing one is reused."
  }

  assert {
    condition     = output.oidc_provider_arn == "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
    error_message = "The output must pass the existing ARN through."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this["deploy"].assume_role_policy).Statement[0].Principal.Federated == "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
    error_message = "Roles must trust the existing provider."
  }
}

run "enterprise_server_issuer_and_custom_audience" {
  command = plan

  variables {
    create_oidc_provider = false
    oidc_provider_url    = "https://ghe.example.com/_services/token"
    oidc_provider_arn    = "arn:aws:iam::111111111111:oidc-provider/ghe.example.com/_services/token"
    audience             = "my-org-deployments"
  }

  assert {
    condition = jsondecode(output.trust_policies["deploy"]).Statement[0].Condition.StringEquals == {
      "ghe.example.com/_services/token:aud" = "my-org-deployments"
      "ghe.example.com/_services/token:sub" = ["repo:my-org/my-app:ref:refs/heads/main"]
    }
    error_message = "Condition keys must be prefixed with the configured issuer and use the configured audience."
  }
}

run "configured_thumbprints_are_passed_through" {
  variables {
    thumbprint_list = ["0123456789abcdef0123456789abcdef01234567"]
  }

  assert {
    condition     = aws_iam_openid_connect_provider.github[0].thumbprint_list == tolist(["0123456789abcdef0123456789abcdef01234567"])
    error_message = "Configured thumbprints must reach the provider."
  }
}

run "rejects_existing_arn_while_creating" {
  command = plan

  variables {
    create_oidc_provider = true
    oidc_provider_arn    = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
  }

  expect_failures = [var.oidc_provider_arn]
}

run "rejects_reuse_without_arn" {
  command = plan

  variables {
    create_oidc_provider = false
  }

  expect_failures = [var.oidc_provider_arn]
}

run "rejects_provider_for_another_issuer" {
  command = plan

  variables {
    create_oidc_provider = false
    oidc_provider_arn    = "arn:aws:iam::111111111111:oidc-provider/accounts.example.com"
  }

  expect_failures = [var.oidc_provider_arn]
}
