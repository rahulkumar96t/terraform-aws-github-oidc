# Renders the sub claims every role trusts and the trust policy documents.
#
# Everything here is plain HCL on purpose: the trust policy is built with
# jsonencode() instead of the aws_iam_policy_document data source, so the exact
# document is known at plan time and can be asserted on in `terraform test`
# with a mocked provider.

locals {
  # Condition keys are "<issuer host and path>:<claim>".
  issuer = trimprefix(var.oidc_provider_url, "https://")

  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.oidc_provider_arn

  # Placeholder context for claim templates without "context": the entry then
  # renders exactly one subject from repository, IDs and claims.
  no_context = { kind = "none", value = "", text = "" }

  # One element per subjects entry, with its effective template and contexts.
  subject_entries = flatten([
    for role_key, role in var.roles : [
      for entry in role.subjects : {
        role_key   = role_key
        entry      = entry
        claim_keys = entry.claim_keys == null ? var.subject_claim_keys : entry.claim_keys
        owner      = split("/", entry.repository)[0]
        name       = split("/", entry.repository)[1]
        contexts = concat(
          [for b in entry.branches : { kind = "ref", value = "refs/heads/${b}", text = "ref:refs/heads/${b}" }],
          [for t in entry.git_tags : { kind = "ref", value = "refs/tags/${t}", text = "ref:refs/tags/${t}" }],
          [for e in entry.environments : { kind = "environment", value = e, text = "environment:${e}" }],
          entry.pull_request ? [{ kind = "pull_request", value = "pull_request", text = "pull_request" }] : [],
        )
      }
    ]
  ])

  # One element per rendered subject: the claim values available to the
  # template for that particular context. Values derived from the repository
  # or the context take precedence over the free-form claims map.
  subject_parts = flatten([
    for e in local.subject_entries : [
      for ctx in(contains(e.claim_keys, "context") ? e.contexts : [local.no_context]) : {
        role_key   = e.role_key
        claim_keys = e.claim_keys
        context    = ctx.text
        repo = (
          e.entry.immutable_subject
          ? "${e.owner}@${e.entry.owner_id}/${e.name}@${e.entry.repository_id}"
          : e.entry.repository
        )
        values = merge(
          e.entry.claims,
          { repository = e.entry.repository, repository_owner = e.owner },
          e.entry.owner_id == null ? {} : { repository_owner_id = e.entry.owner_id },
          e.entry.repository_id == null ? {} : { repository_id = e.entry.repository_id },
          ctx.kind == "ref" ? { ref = ctx.value } : {},
          ctx.kind == "environment" ? { environment = ctx.value } : {},
        )
      }
    ]
  ])

  structured_subjects = [
    for p in local.subject_parts : {
      role_key = p.role_key
      subject = join(":", [
        for key in p.claim_keys : (
          key == "repo" ? "repo:${p.repo}" :
          key == "context" ? p.context :
          "${key}:${p.values[key]}"
        )
      ])
    }
  ]

  role_subjects = {
    for role_key, role in var.roles : role_key => distinct(concat(
      [for s in local.structured_subjects : s.subject if s.role_key == role_key],
      role.custom_subjects,
    ))
  }

  # Validation guarantees that * and ? only appear when the role opted in with
  # wildcard_match, so their presence decides the operator.
  split_subjects = {
    for role_key, subjects in local.role_subjects : role_key => {
      exact    = [for s in subjects : s if !can(regex("[*?]", s))]
      wildcard = [for s in subjects : s if can(regex("[*?]", s))]
    }
  }

  trust_policies = {
    for role_key, s in local.split_subjects : role_key => jsonencode({
      Version = "2012-10-17"
      Statement = concat(
        length(s.exact) == 0 ? [] : [{
          Sid       = "GitHubActionsExactSubjects"
          Effect    = "Allow"
          Principal = { Federated = local.oidc_provider_arn }
          Action    = "sts:AssumeRoleWithWebIdentity"
          Condition = {
            StringEquals = {
              "${local.issuer}:aud" = var.audience
              "${local.issuer}:sub" = s.exact
            }
          }
        }],
        length(s.wildcard) == 0 ? [] : [{
          Sid       = "GitHubActionsWildcardSubjects"
          Effect    = "Allow"
          Principal = { Federated = local.oidc_provider_arn }
          Action    = "sts:AssumeRoleWithWebIdentity"
          Condition = {
            StringEquals = {
              "${local.issuer}:aud" = var.audience
            }
            StringLike = {
              "${local.issuer}:sub" = s.wildcard
            }
          }
        }],
      )
    })
  }
}
