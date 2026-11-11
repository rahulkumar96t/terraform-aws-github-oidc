# Customised subject claim templates (include_claim_keys) and the immutable
# repo:OWNER@ID/REPO@ID format.

mock_provider "aws" {
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
    }
  }
}

run "module_wide_template_with_numeric_ids" {
  variables {
    subject_claim_keys = ["repository_owner_id", "repository_id", "context"]
    roles = {
      deploy = {
        subjects = [{
          repository    = "my-org/my-app"
          owner_id      = "1001"
          repository_id = "2002"
          branches      = ["main"]
          environments  = ["production"]
        }]
      }
    }
  }

  assert {
    condition = jsondecode(output.trust_policies["deploy"]).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == [
      "repository_owner_id:1001:repository_id:2002:ref:refs/heads/main",
      "repository_owner_id:1001:repository_id:2002:environment:production",
    ]
    error_message = "Subjects must follow the configured claim key order with the numeric IDs."
  }
}

run "per_repository_template_with_reusable_workflow_claim" {
  variables {
    roles = {
      deploy = {
        subjects = [
          { repository = "my-org/legacy-app", branches = ["main"] },
          {
            repository   = "my-org/my-app"
            environments = ["prod"]
            claim_keys   = ["repo", "context", "job_workflow_ref"]
            claims = {
              job_workflow_ref = "my-org/shared-workflows/.github/workflows/deploy.yml@refs/heads/main"
            }
          },
        ]
      }
    }
  }

  assert {
    condition = output.role_subjects["deploy"] == tolist([
      "repo:my-org/legacy-app:ref:refs/heads/main",
      "repo:my-org/my-app:environment:prod:job_workflow_ref:my-org/shared-workflows/.github/workflows/deploy.yml@refs/heads/main",
    ])
    error_message = "claim_keys must only change the format of its own entry."
  }
}

run "immutable_subject_format" {
  variables {
    roles = {
      deploy = {
        subjects = [{
          repository        = "my-org/my-app"
          immutable_subject = true
          owner_id          = "1001"
          repository_id     = "2002"
          branches          = ["main"]
        }]
      }
    }
  }

  assert {
    condition     = output.role_subjects["deploy"] == tolist(["repo:my-org@1001/my-app@2002:ref:refs/heads/main"])
    error_message = "Immutable subjects must render repo:OWNER@OWNER_ID/REPO@REPO_ID."
  }
}

run "ref_claim_is_derived_for_branches_and_taken_from_claims_for_environments" {
  variables {
    subject_claim_keys = ["repo", "context", "ref"]
    roles = {
      release = {
        subjects = [
          { repository = "my-org/my-app", git_tags = ["v2.0.0"] },
          { repository = "my-org/my-app", environments = ["production"], claims = { ref = "refs/heads/main" } },
        ]
      }
    }
  }

  assert {
    condition = output.role_subjects["release"] == tolist([
      "repo:my-org/my-app:ref:refs/tags/v2.0.0:ref:refs/tags/v2.0.0",
      "repo:my-org/my-app:environment:production:ref:refs/heads/main",
    ])
    error_message = "ref must come from the tag context, or from claims when the context is an environment."
  }
}

run "template_without_context_renders_one_subject_per_entry" {
  variables {
    roles = {
      read-only = {
        subjects = [{
          repository    = "my-org/my-app"
          claim_keys    = ["repository_id", "workflow"]
          repository_id = "2002"
          claims        = { workflow = "nightly-audit" }
        }]
      }
    }
  }

  assert {
    condition     = output.role_subjects["read-only"] == tolist(["repository_id:2002:workflow:nightly-audit"])
    error_message = "Without a context key the entry must render exactly one subject from IDs and claims."
  }
}
