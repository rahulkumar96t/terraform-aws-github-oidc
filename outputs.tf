output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider the roles trust (created by this module or passed in)."
  value       = local.oidc_provider_arn
}

output "role_arns" {
  description = "Role ARNs keyed like var.roles. Use them as role-to-assume in workflows."
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}

output "role_names" {
  description = "Role names keyed like var.roles."
  value       = { for k, r in aws_iam_role.this : k => r.name }
}

output "role_subjects" {
  description = "Rendered sub claims each role trusts, keyed like var.roles. Handy for reviewing a plan."
  value       = local.role_subjects
}

output "trust_policies" {
  description = "Trust policy JSON documents keyed like var.roles."
  value       = local.trust_policies
}
