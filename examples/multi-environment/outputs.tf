output "role_arns" {
  description = "Role ARNs per environment. Store them as GitHub environment variables (AWS_ROLE_ARN)."
  value       = module.github_oidc.role_arns
}

output "role_subjects" {
  description = "The sub claims each role accepts."
  value       = module.github_oidc.role_subjects
}

output "trust_policies" {
  description = "Rendered trust policies, for review."
  value       = module.github_oidc.trust_policies
}
