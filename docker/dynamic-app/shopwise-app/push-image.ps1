# Define repository name and region
$repoName = "shopwise"
$region = "us-east-1"
$accountId = "651783246143"

# Attempt to describe the repository
$repoExists = aws ecr describe-repositories --repository-names $repoName --region $region

# Check if the last command succeeded
if ($?) {
    Write-Host "Repository already exists. Skipping creation."
} else {
    Write-Host "Repository does not exist. Creating repository..."
    aws ecr create-repository --repository-name $repoName --region $region
}

# Tag the Docker image with the ECR repository URI
docker tag $repoName $accountId.dkr.ecr.$region.amazonaws.com/$repoName

# Retrieve an authentication token and log in to the ECR registry
aws ecr get-login-password | docker login --username AWS --password-stdin $accountId.dkr.ecr.$region.amazonaws.com

# Push the Docker image to the ECR repository
docker push $accountId.dkr.ecr.$region.amazonaws.com/$repoName
