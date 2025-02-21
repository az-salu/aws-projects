# project notes 

Add IAM principals to your Amazon EKS cluster:
https://docs.aws.amazon.com/eks/latest/userguide/auth-configmap.html#aws-auth-users

Allow script execution on Windows
1. Open PowerShell as Administrator
2. Run the Following Command:
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
