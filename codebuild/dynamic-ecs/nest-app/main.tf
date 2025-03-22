locals {
  region                 = "us-east-1"
  project_name           = "nest"
  environment            = "dev"
  secret_arn             = "arn:aws:secretsmanager:us-east-1:651783246143:secret:app-secrets-ATCH9v"
  source_branch          = "main"
  build_environment_type = "LINUX_CONTAINER"
  build_compute_type     = "BUILD_GENERAL1_SMALL" # Possible values: BUILD_GENERAL1_SMALL | BUILD_GENERAL1_MEDIUM | BUILD_GENERAL1_LARGE
  build_image            = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
  github_username        = "az-salu"
  source_type            = "GITHUB"
  source_location        = "https://github.com/az-salu/aws-projects.git"
  buildspec_file         = "codebuild/dynamic-ecs/nest-app/buildspec.yml"
}

module "nest-app" {
  source = "../infrastructure"

  region                 = local.region
  project_name           = local.project_name
  environment            = local.environment
  secret_arn             = local.secret_arn
  source_branch          = local.source_branch
  build_environment_type = local.build_environment_type
  build_compute_type     = local.build_compute_type
  build_image            = local.build_image
  github_username        = local.github_username
  source_type            = local.source_type
  source_location        = local.source_location
  buildspec_file         = local.buildspec_file
}