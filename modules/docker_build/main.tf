locals {
  impersonation_arg = var.impersonate_service_account != "" ? "--impersonate-service-account=${var.impersonate_service_account}" : ""

  tracked_files = sort(tolist(toset(concat(
    tolist(fileset(var.context_path, "Dockerfile")),
    tolist(fileset(var.context_path, "*.txt")),
    tolist(fileset(var.context_path, "*.yml")),
    tolist(fileset(var.context_path, "*.yaml")),
    tolist(fileset(var.context_path, "models/**/*")),
    tolist(fileset(var.context_path, "macros/**/*")),
    tolist(fileset(var.context_path, "seeds/**/*")),
    tolist(fileset(var.context_path, "snapshots/**/*")),
    tolist(fileset(var.context_path, "tests/**/*")),
  ))))

  source_hash = sha256(join(",", [
    for f in local.tracked_files :
    "${f}:${filesha256("${var.context_path}/${f}")}"
  ]))
}

resource "null_resource" "build_push" {
  triggers = {
    source_hash = local.source_hash
    image_url   = var.image_url
  }

  # Submits the build to Cloud Build — no local Docker daemon required.
  # The build runs entirely in GCP and pushes directly to Artifact Registry.
  provisioner "local-exec" {
    command = <<-EOT
      gcloud builds submit \
        --tag ${var.image_url} \
        --project ${var.project_id} \
        ${local.impersonation_arg} \
        ${var.context_path}
    EOT
  }
}
