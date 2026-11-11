###############################################################################
# Identity provider
###############################################################################

variable "create_oidc_provider" {
  description = "Create the IAM OIDC identity provider for GitHub Actions. An account can hold only one provider per issuer URL, so set this to false and pass oidc_provider_arn when another stack already owns it."
  type        = bool
  default     = true
  nullable    = false
}

variable "oidc_provider_arn" {
  description = "ARN of an existing IAM OIDC provider for the issuer in oidc_provider_url. Required when create_oidc_provider is false and must be null otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.create_oidc_provider != (var.oidc_provider_arn != null)
    error_message = "Set exactly one of create_oidc_provider = true or oidc_provider_arn."
  }

  validation {
    condition     = var.oidc_provider_arn == null ? true : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:oidc-provider/.+$", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must look like arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com."
  }

  validation {
    # The trust policy condition keys are derived from the issuer URL. A provider
    # for a different issuer would produce a policy that can never match.
    condition     = var.oidc_provider_arn == null ? true : endswith(var.oidc_provider_arn, ":oidc-provider/${trimprefix(var.oidc_provider_url, "https://")}")
    error_message = "oidc_provider_arn must belong to the issuer in oidc_provider_url (expected the ARN to end in \":oidc-provider/${trimprefix(var.oidc_provider_url, "https://")}\")."
  }
}

variable "oidc_provider_url" {
  description = "Issuer URL of the GitHub Actions OIDC tokens. Change it only for GitHub Enterprise Server (https://HOST/_services/token) or an enterprise-specific issuer."
  type        = string
  default     = "https://token.actions.githubusercontent.com"
  nullable    = false

  validation {
    condition     = can(regex("^https://[A-Za-z0-9.-]+(/[A-Za-z0-9._~/-]*[A-Za-z0-9._~-])?$", var.oidc_provider_url))
    error_message = "oidc_provider_url must be an https:// URL without a trailing slash, query or fragment."
  }
}

variable "audience" {
  description = "Expected aud claim. It is registered as the provider's client ID and required by every trust policy. Keep the default unless the workflow passes a custom audience to configure-aws-credentials."
  type        = string
  default     = "sts.amazonaws.com"
  nullable    = false

  validation {
    condition     = length(var.audience) > 0 && !can(regex("[*?]", var.audience))
    error_message = "audience must be a non-empty literal string (no wildcards)."
  }
}

variable "thumbprint_list" {
  description = "Optional server certificate thumbprints for the provider. AWS validates GitHub's issuer against its own trusted CA library and ignores this list for token.actions.githubusercontent.com; it only matters for self-hosted issuers."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for t in var.thumbprint_list : can(regex("^[0-9a-fA-F]{40}$", t))])
    error_message = "Each thumbprint must be a 40-character hex SHA-1 fingerprint."
  }
}

###############################################################################
# Subject rendering defaults
###############################################################################

variable "subject_claim_keys" {
  description = "Claim keys that make up the sub claim, in order, as configured on GitHub with include_claim_keys. The default [\"repo\", \"context\"] is GitHub's default format repo:OWNER/REPO:<context>. Individual subject entries can override it with claim_keys."
  type        = list(string)
  default     = ["repo", "context"]
  nullable    = false

  validation {
    condition = (
      length(var.subject_claim_keys) > 0 &&
      length(distinct(var.subject_claim_keys)) == length(var.subject_claim_keys) &&
      alltrue([for k in var.subject_claim_keys : can(regex("^[a-z][a-z_]*$", k))])
    )
    error_message = "subject_claim_keys must be a non-empty list of distinct lower-case claim names such as repo, context, ref or repository_id."
  }
}

variable "allow_wildcard_subjects" {
  description = "Allow subjects whose wildcard spans repositories or every ref of a repository, such as \"*\", \"repo:my-org/*\" or \"repo:my-org/my-app:*\". Leave false unless you have reviewed who can run workflows in every repository the pattern matches."
  type        = bool
  default     = false
  nullable    = false
}

variable "tags" {
  description = "Tags applied to every resource the module creates. Role-level tags are merged on top."
  type        = map(string)
  default     = {}
  nullable    = false
}

###############################################################################
# Roles
###############################################################################

variable "roles" {
  description = <<-EOT
    IAM roles to create, keyed by a stable identifier (also the default role name).

    Trust is described by `subjects` (structured, preferred) and/or `custom_subjects`
    (raw sub strings). Every rendered subject is matched with StringEquals unless the
    role sets `wildcard_match = true`, in which case only the values containing * or ?
    move to a separate StringLike statement.

    subjects[*] fields:
      repository        "OWNER/REPO"
      branches          branch names -> context ref:refs/heads/NAME
      git_tags          tag names    -> context ref:refs/tags/NAME
      environments      GitHub environment names -> context environment:NAME
      pull_request      true adds the context pull_request (off by default)
      claim_keys        per-repository override of var.subject_claim_keys
      immutable_subject true for the repo:OWNER@OWNER_ID/REPO@REPO_ID format
      owner_id          numeric owner ID (immutable format, repository_owner_id key)
      repository_id     numeric repository ID (immutable format, repository_id key)
      claims            values for any other claim key in the template (e.g. ref, job_workflow_ref)
  EOT

  type = map(object({
    name                 = optional(string)
    description          = optional(string, "Assumed by GitHub Actions through OIDC")
    path                 = optional(string, "/")
    max_session_duration = optional(number, 3600)
    permissions_boundary = optional(string)
    managed_policy_arns  = optional(map(string), {})
    inline_policies      = optional(map(string), {})
    tags                 = optional(map(string), {})
    wildcard_match       = optional(bool, false)
    custom_subjects      = optional(list(string), [])
    subjects = optional(list(object({
      repository        = string
      branches          = optional(list(string), [])
      git_tags          = optional(list(string), [])
      environments      = optional(list(string), [])
      pull_request      = optional(bool, false)
      claim_keys        = optional(list(string))
      immutable_subject = optional(bool, false)
      owner_id          = optional(string)
      repository_id     = optional(string)
      claims            = optional(map(string), {})
    })), [])
  }))
  default  = {}
  nullable = false

  # --- IAM role attributes ---------------------------------------------------

  validation {
    condition     = alltrue([for k, r in var.roles : can(regex("^[\\w+=,.@-]{1,64}$", coalesce(r.name, k)))])
    error_message = "Role names (the map key unless name is set) must be 1-64 characters from A-Z a-z 0-9 and +=,.@_-."
  }

  validation {
    condition     = alltrue([for r in values(var.roles) : can(regex("^/([!-~]+/)?$", r.path)) && length(r.path) <= 512])
    error_message = "path must start and end with / (for example / or /github-actions/)."
  }

  validation {
    condition     = alltrue([for r in values(var.roles) : r.max_session_duration >= 3600 && r.max_session_duration <= 43200 && floor(r.max_session_duration) == r.max_session_duration])
    error_message = "max_session_duration must be a whole number of seconds between 3600 (1 hour) and 43200 (12 hours)."
  }

  validation {
    condition     = alltrue([for r in values(var.roles) : r.permissions_boundary == null ? true : can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/.+$", r.permissions_boundary))])
    error_message = "permissions_boundary must be an IAM managed policy ARN."
  }

  validation {
    condition     = alltrue(flatten([for r in values(var.roles) : [for arn in values(r.managed_policy_arns) : can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/.+$", arn))]]))
    error_message = "managed_policy_arns values must be IAM managed policy ARNs (the map keys are only stable labels)."
  }

  validation {
    condition = alltrue(flatten([for r in values(var.roles) : [
      for name, doc in r.inline_policies : can(regex("^[\\w+=,.@-]{1,128}$", name)) && can(jsondecode(doc))
    ]]))
    error_message = "inline_policies must map policy names (1-128 characters from A-Z a-z 0-9 and +=,.@_-) to JSON policy documents."
  }

  # --- Subjects: shape ---------------------------------------------------------

  validation {
    condition     = alltrue([for r in values(var.roles) : length(r.subjects) + length(r.custom_subjects) > 0])
    error_message = "Every role needs at least one subject. Roles with an empty subject list: ${join(", ", [for k, r in var.roles : k if length(r.subjects) + length(r.custom_subjects) == 0])}."
  }

  validation {
    condition = alltrue(flatten([for r in values(var.roles) : [
      for s in r.subjects : can(regex("^[A-Za-z0-9*?-]+/[A-Za-z0-9._*?-]+$", s.repository))
    ]]))
    error_message = "subjects[*].repository must be OWNER/REPO, for example my-org/my-app."
  }

  validation {
    condition = alltrue(flatten([for r in values(var.roles) : [
      for s in r.subjects : s.claim_keys == null ? true : (
        length(s.claim_keys) > 0 &&
        length(distinct(s.claim_keys)) == length(s.claim_keys) &&
        alltrue([for k in s.claim_keys : can(regex("^[a-z][a-z_]*$", k))])
      )
    ]]))
    error_message = "subjects[*].claim_keys must be null or a non-empty list of distinct lower-case claim names."
  }

  validation {
    # With "context" in the template each context (branch, tag, environment,
    # pull request) becomes one subject, so at least one is needed. Without it
    # the contexts would silently not be enforced, so they are rejected.
    condition = alltrue(flatten([for r in values(var.roles) : [
      for s in r.subjects : contains(s.claim_keys == null ? var.subject_claim_keys : s.claim_keys, "context") == (
        length(s.branches) + length(s.git_tags) + length(s.environments) + (s.pull_request ? 1 : 0) > 0
      )
    ]]))
    error_message = "When the claim template contains \"context\", each subjects entry needs at least one of branches, git_tags, environments or pull_request = true. When it does not, those fields cannot be enforced and must be left empty."
  }

  validation {
    condition = alltrue(flatten([for r in values(var.roles) : [
      for s in r.subjects : [
        for key in(s.claim_keys == null ? var.subject_claim_keys : s.claim_keys) : (
          contains(["repo", "context", "repository", "repository_owner"], key) ||
          contains(keys(s.claims), key) ||
          (key == "repository_owner_id" && s.owner_id != null) ||
          (key == "repository_id" && s.repository_id != null) ||
          (key == "ref" && length(s.branches) + length(s.git_tags) > 0 && length(s.environments) == 0 && !s.pull_request) ||
          (key == "environment" && length(s.environments) > 0 && length(s.branches) + length(s.git_tags) == 0 && !s.pull_request)
        )
      ]
    ]]))
    error_message = "Every claim key in the template needs a value. repo, context, repository and repository_owner come from repository; repository_owner_id and repository_id from owner_id and repository_id; ref is derived only when every context of the entry is a branch or tag, environment only when every context is an environment. Put any other value in claims."
  }

  validation {
    condition = alltrue(flatten([for r in values(var.roles) : [
      for s in r.subjects : (
        (s.immutable_subject ? s.owner_id != null && s.repository_id != null : true) &&
        (s.owner_id == null ? true : can(regex("^[0-9]+$", s.owner_id))) &&
        (s.repository_id == null ? true : can(regex("^[0-9]+$", s.repository_id)))
      )
    ]]))
    error_message = "owner_id and repository_id must be numeric GitHub IDs, and immutable_subject = true requires both."
  }

  validation {
    # GitHub escapes ":" inside claim values. Rejecting it keeps the rendered
    # subject identical to the token instead of guessing the encoding.
    condition = alltrue(flatten([for r in values(var.roles) : [
      for s in r.subjects : [
        for v in concat(s.branches, s.git_tags, s.environments, values(s.claims)) : length(v) > 0 && !strcontains(v, ":")
      ]
    ]]))
    error_message = "Branch, tag, environment and claim values must be non-empty and must not contain \":\". Use custom_subjects for unusual names."
  }

  # --- Subjects: wildcards -----------------------------------------------------

  validation {
    condition = alltrue([for r in values(var.roles) : r.wildcard_match || !anytrue([
      for v in concat(r.custom_subjects, flatten([
        for s in r.subjects : concat([s.repository], s.branches, s.git_tags, s.environments, values(s.claims))
      ])) : can(regex("[*?]", v))
    ])])
    error_message = "Subjects contain * or ?, which StringEquals would compare literally. Set wildcard_match = true on these roles to opt in to StringLike: ${join(", ", [for k, r in var.roles : k if !r.wildcard_match && anytrue([for v in concat(r.custom_subjects, flatten([for s in r.subjects : concat([s.repository], s.branches, s.git_tags, s.environments, values(s.claims))])) : can(regex("[*?]", v))])])}."
  }

  validation {
    # "Broad" means the wildcard is not confined to a ref or environment name of
    # a single repository: a bare "*", a wildcard inside the repository segment
    # (repo:my-org/*), or "any context" of a repository (repo:my-org/my-app:*).
    condition = var.allow_wildcard_subjects || alltrue(flatten([for r in values(var.roles) : concat(
      [for s in r.subjects : !can(regex("[*?]", s.repository))],
      [for s in r.subjects : !anytrue([
        for key, value in s.claims : contains(["repo", "repository", "repository_id", "repository_owner", "repository_owner_id"], key) && can(regex("[*?]", value))
      ])],
      [for cs in r.custom_subjects : !can(regex("^[*?:]*$|(^|:)(repo|repository|repository_id|repository_owner|repository_owner_id):[^:]*[*?]|^repo:[^:]+:[*]+$", cs))],
    )]))
    error_message = "Subjects such as \"*\", \"repo:my-org/*\" or \"repo:my-org/my-app:*\" trust every repository or every ref they match. Narrow them, or set allow_wildcard_subjects = true if that is really intended."
  }
}
