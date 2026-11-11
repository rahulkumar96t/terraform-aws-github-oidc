# Decodes the rendered trust policy and asserts on the exact conditions.

mock_provider "aws" {
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
    }
  }
}

run "branches_and_tags_render_exact_default_subjects" {
  variables {
    roles = {
      deploy = {
        subjects = [{
          repository = "my-org/my-app"
          branches   = ["main", "release/2026"]
          git_tags   = ["v1.0.0"]
        }]
      }
    }
  }

  assert {
    condition     = length(jsondecode(output.trust_policies["deploy"]).Statement) == 1
    error_message = "Exact subjects must produce exactly one statement."
  }

  assert {
    condition = jsondecode(output.trust_policies["deploy"]).Statement[0].Condition == {
      StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = [
          "repo:my-org/my-app:ref:refs/heads/main",
          "repo:my-org/my-app:ref:refs/heads/release/2026",
          "repo:my-org/my-app:ref:refs/tags/v1.0.0",
        ]
      }
    }
    error_message = "Condition block must be StringEquals on aud and the exact sub list, nothing else."
  }

  assert {
    condition     = jsondecode(output.trust_policies["deploy"]).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
    error_message = "Trust policy must only allow sts:AssumeRoleWithWebIdentity."
  }

  assert {
    condition     = jsondecode(output.trust_policies["deploy"]).Statement[0].Principal.Federated == "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
    error_message = "Principal must be the created OIDC provider."
  }

  assert {
    condition     = aws_iam_role.this["deploy"].assume_role_policy == output.trust_policies["deploy"]
    error_message = "The role must use the rendered trust policy."
  }
}

run "environments_render_environment_context" {
  variables {
    roles = {
      deploy = {
        subjects = [{
          repository   = "my-org/my-app"
          environments = ["staging", "production"]
        }]
      }
    }
  }

  assert {
    condition = jsondecode(output.trust_policies["deploy"]).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == [
      "repo:my-org/my-app:environment:staging",
      "repo:my-org/my-app:environment:production",
    ]
    error_message = "Environment subjects must use the environment:NAME context."
  }
}

run "pull_request_is_off_unless_requested" {
  variables {
    roles = {
      default_off = {
        subjects = [{ repository = "my-org/my-app", branches = ["main"] }]
      }
      opted_in = {
        subjects = [{ repository = "my-org/my-app", pull_request = true }]
      }
    }
  }

  assert {
    condition     = output.role_subjects["default_off"] == tolist(["repo:my-org/my-app:ref:refs/heads/main"])
    error_message = "A role must not trust pull_request subjects unless pull_request = true."
  }

  assert {
    condition     = output.role_subjects["opted_in"] == tolist(["repo:my-org/my-app:pull_request"])
    error_message = "pull_request = true must add the repo:OWNER/REPO:pull_request subject."
  }
}

run "wildcard_match_moves_only_patterns_to_string_like" {
  variables {
    roles = {
      dev = {
        wildcard_match = true
        subjects = [{
          repository = "my-org/my-app"
          branches   = ["main", "feature/*"]
        }]
      }
    }
  }

  assert {
    condition     = length(jsondecode(output.trust_policies["dev"]).Statement) == 2
    error_message = "Mixed exact and wildcard subjects must be split into two statements."
  }

  assert {
    condition = jsondecode(output.trust_policies["dev"]).Statement[0].Condition == {
      StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = ["repo:my-org/my-app:ref:refs/heads/main"]
      }
    }
    error_message = "Literal subjects must stay under StringEquals even when the role opts in to wildcards."
  }

  assert {
    condition = jsondecode(output.trust_policies["dev"]).Statement[1].Condition == {
      StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
      }
      StringLike = {
        "token.actions.githubusercontent.com:sub" = ["repo:my-org/my-app:ref:refs/heads/feature/*"]
      }
    }
    error_message = "Only the pattern goes to StringLike, and aud stays an exact match."
  }
}

run "custom_subjects_are_exact_and_deduplicated" {
  variables {
    roles = {
      deploy = {
        subjects        = [{ repository = "my-org/my-app", branches = ["main"] }]
        custom_subjects = ["repo:my-org/my-app:ref:refs/heads/main", "repo:my-org/my-app:environment:Prod Ops"]
      }
    }
  }

  assert {
    condition = jsondecode(output.trust_policies["deploy"]).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == [
      "repo:my-org/my-app:ref:refs/heads/main",
      "repo:my-org/my-app:environment:Prod Ops",
    ]
    error_message = "custom_subjects must be appended verbatim and duplicates removed."
  }

  assert {
    condition     = !contains(keys(jsondecode(output.trust_policies["deploy"]).Statement[0].Condition), "StringLike")
    error_message = "A role without wildcard_match must never get a StringLike condition."
  }
}

run "every_role_gets_its_own_trust_policy" {
  variables {
    roles = {
      app-a = { subjects = [{ repository = "my-org/app-a", branches = ["main"] }] }
      app-b = { subjects = [{ repository = "my-org/app-b", environments = ["production"] }] }
    }
  }

  assert {
    condition     = output.role_subjects["app-a"] == tolist(["repo:my-org/app-a:ref:refs/heads/main"])
    error_message = "app-a must only trust its own repository."
  }

  assert {
    condition     = output.role_subjects["app-b"] == tolist(["repo:my-org/app-b:environment:production"])
    error_message = "app-b must only trust its own repository."
  }

  assert {
    condition     = output.role_names == { app-a = "app-a", app-b = "app-b" }
    error_message = "Role names default to the map keys."
  }
}
