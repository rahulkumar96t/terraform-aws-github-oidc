# Inputs the module must refuse at plan time. Each run breaks exactly one rule.

mock_provider "aws" {}

variables {
  create_oidc_provider = false
  oidc_provider_arn    = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
}

# --- Wildcards -------------------------------------------------------------

run "rejects_bare_star_subject" {
  command = plan

  variables {
    roles = {
      anything = {
        wildcard_match  = true
        custom_subjects = ["*"]
      }
    }
  }

  expect_failures = [var.roles]
}

run "rejects_org_wide_subject" {
  command = plan

  variables {
    roles = {
      org = {
        wildcard_match  = true
        custom_subjects = ["repo:my-org/*"]
      }
    }
  }

  expect_failures = [var.roles]
}

run "rejects_any_ref_of_a_repository" {
  command = plan

  variables {
    roles = {
      any-ref = {
        wildcard_match  = true
        custom_subjects = ["repo:my-org/my-app:*"]
      }
    }
  }

  expect_failures = [var.roles]
}

run "rejects_wildcard_in_structured_repository" {
  command = plan

  variables {
    roles = {
      org = {
        wildcard_match = true
        subjects       = [{ repository = "my-org/*", branches = ["main"] }]
      }
    }
  }

  expect_failures = [var.roles]
}

run "allows_broad_subjects_only_with_explicit_opt_in" {
  command = plan

  variables {
    allow_wildcard_subjects = true
    roles = {
      org = {
        wildcard_match  = true
        custom_subjects = ["repo:my-org/*"]
      }
    }
  }

  assert {
    condition = jsondecode(output.trust_policies["org"]).Statement[0].Condition.StringLike == {
      "token.actions.githubusercontent.com:sub" = ["repo:my-org/*"]
    }
    error_message = "With both opt-ins the org-wide pattern is rendered under StringLike."
  }
}

run "rejects_wildcard_without_wildcard_match" {
  command = plan

  variables {
    roles = {
      dev = {
        subjects = [{ repository = "my-org/my-app", branches = ["feature/*"] }]
      }
    }
  }

  expect_failures = [var.roles]
}

# --- Subject shape -----------------------------------------------------------

run "rejects_empty_subject_list" {
  command = plan

  variables {
    roles = {
      nobody = {
        managed_policy_arns = { ro = "arn:aws:iam::aws:policy/ReadOnlyAccess" }
      }
    }
  }

  expect_failures = [var.roles]
}

run "rejects_entry_without_any_context" {
  command = plan

  variables {
    roles = {
      deploy = {
        subjects = [{ repository = "my-org/my-app" }]
      }
    }
  }

  expect_failures = [var.roles]
}

run "rejects_contexts_the_template_cannot_enforce" {
  command = plan

  variables {
    roles = {
      deploy = {
        subjects = [{
          repository    = "my-org/my-app"
          claim_keys    = ["repository_id"]
          repository_id = "2002"
          branches      = ["main"]
        }]
      }
    }
  }

  expect_failures = [var.roles]
}

run "rejects_template_key_without_value" {
  command = plan

  variables {
    roles = {
      deploy = {
        subjects = [{
          repository   = "my-org/my-app"
          claim_keys   = ["repo", "context", "job_workflow_ref"]
          environments = ["production"]
        }]
      }
    }
  }

  expect_failures = [var.roles]
}

run "rejects_ref_key_for_environment_without_claim" {
  command = plan

  variables {
    subject_claim_keys = ["repo", "context", "ref"]
    roles = {
      prod = {
        subjects = [{ repository = "my-org/my-app", environments = ["production"] }]
      }
    }
  }

  expect_failures = [var.roles]
}

run "rejects_immutable_subject_without_ids" {
  command = plan

  variables {
    roles = {
      deploy = {
        subjects = [{ repository = "my-org/my-app", immutable_subject = true, branches = ["main"] }]
      }
    }
  }

  expect_failures = [var.roles]
}

run "rejects_colon_in_environment_name" {
  command = plan

  variables {
    roles = {
      deploy = {
        subjects = [{ repository = "my-org/my-app", environments = ["prod:eu"] }]
      }
    }
  }

  expect_failures = [var.roles]
}

run "rejects_malformed_repository" {
  command = plan

  variables {
    roles = {
      deploy = {
        subjects = [{ repository = "my-app", branches = ["main"] }]
      }
    }
  }

  expect_failures = [var.roles]
}

# --- Role attributes ---------------------------------------------------------

run "rejects_session_longer_than_twelve_hours" {
  command = plan

  variables {
    roles = {
      deploy = {
        max_session_duration = 50000
        subjects             = [{ repository = "my-org/my-app", branches = ["main"] }]
      }
    }
  }

  expect_failures = [var.roles]
}

run "rejects_invalid_permissions_boundary" {
  command = plan

  variables {
    roles = {
      deploy = {
        permissions_boundary = "deploy-boundary"
        subjects             = [{ repository = "my-org/my-app", branches = ["main"] }]
      }
    }
  }

  expect_failures = [var.roles]
}

run "rejects_inline_policy_that_is_not_json" {
  command = plan

  variables {
    roles = {
      deploy = {
        inline_policies = { broken = "{ not json" }
        subjects        = [{ repository = "my-org/my-app", branches = ["main"] }]
      }
    }
  }

  expect_failures = [var.roles]
}

run "rejects_invalid_role_name" {
  command = plan

  variables {
    roles = {
      "deploy role" = {
        subjects = [{ repository = "my-org/my-app", branches = ["main"] }]
      }
    }
  }

  expect_failures = [var.roles]
}
