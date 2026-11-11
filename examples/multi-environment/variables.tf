variable "region" {
  description = "AWS region for the provider. IAM is global, the region only matters for the API endpoint."
  type        = string
  default     = "eu-central-1"
}

variable "oidc_provider_arn" {
  description = "ARN of the existing GitHub Actions OIDC provider in this account."
  type        = string
  default     = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
}

variable "prod_permissions_boundary" {
  description = "Permissions boundary for the production role."
  type        = string
  default     = "arn:aws:iam::111111111111:policy/github-actions-boundary"
}
