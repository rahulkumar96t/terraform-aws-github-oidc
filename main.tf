resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = var.oidc_provider_url
  client_id_list = [var.audience]
  # GitHub's issuer is validated against AWS's trusted CA library, so an empty
  # list is the normal case. null lets IAM decide instead of storing [].
  thumbprint_list = length(var.thumbprint_list) > 0 ? var.thumbprint_list : null

  tags = var.tags
}

resource "aws_iam_role" "this" {
  for_each = var.roles

  name                  = coalesce(each.value.name, each.key)
  path                  = each.value.path
  description           = each.value.description
  assume_role_policy    = local.trust_policies[each.key]
  max_session_duration  = each.value.max_session_duration
  permissions_boundary  = each.value.permissions_boundary
  force_detach_policies = true

  tags = merge(var.tags, each.value.tags)
}

locals {
  # Keyed by "<role>/<label>" so that the for_each keys are known at plan time
  # even when the policy ARN itself is created in the same apply.
  managed_policy_attachments = merge([
    for role_key, role in var.roles : {
      for label, arn in role.managed_policy_arns : "${role_key}/${label}" => {
        role_key   = role_key
        policy_arn = arn
      }
    }
  ]...)

  inline_policies = merge([
    for role_key, role in var.roles : {
      for name, document in role.inline_policies : "${role_key}/${name}" => {
        role_key = role_key
        name     = name
        policy   = document
      }
    }
  ]...)
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = local.managed_policy_attachments

  role       = aws_iam_role.this[each.value.role_key].name
  policy_arn = each.value.policy_arn
}

resource "aws_iam_role_policy" "inline" {
  for_each = local.inline_policies

  name   = each.value.name
  role   = aws_iam_role.this[each.value.role_key].name
  policy = each.value.policy
}

# IAM rejects trust policies above the account's "role trust policy length"
# quota (2,048 characters by default; it can be raised). This only warns, so a
# raised quota does not block the apply.
check "trust_policy_size" {
  assert {
    condition     = alltrue([for p in values(local.trust_policies) : length(p) <= 2048])
    error_message = "Trust policies longer than 2,048 characters: ${join(", ", [for k, p in local.trust_policies : k if length(p) > 2048])}. Raise the IAM quota, use fewer subjects per role or split the role."
  }
}
