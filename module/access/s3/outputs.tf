output "actions" {
  description = "The fixed S3 action preset granted to a team's role."
  value       = local.actions
}

output "policy" {
  description = "Rendered S3 access policy document (JSON), scoped to var.resources. Attached verbatim by the composition root."
  value       = local.policy
}