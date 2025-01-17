# export the iam role name
output "ec2_instance_profile_role_name" {
  value = aws_iam_instance_profile.s3_full_access_instance_profile.name
}