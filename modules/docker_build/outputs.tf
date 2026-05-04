output "image_url" {
  description = "The image URL that was built and pushed."
  value       = var.image_url
}

output "source_hash" {
  description = "Hash of the source files used to trigger the last build."
  value       = local.source_hash
}
