## 📚 Course Title  
1. How to Host an HTML Application on AWS (Full Step-by-Step Project)

Welcome to "How to Host an HTML Application on AWS" — a full step-by-step project for beginners.  
In this course, you’ll learn how to build and deploy a secure HTML web application using core AWS services.  
 
First, we’ll set up networking using a custom VPC, public and private subnets, an Internet Gateway, a NAT Gateway, and route tables to manage traffic.  
 
Then, you’ll use S3 to store the HTML application code, and configure an IAM role to allow secure access from your EC2 instance.  
 
After that, we’ll launch and connect to a Linux EC2 instance using SSH keys, and install the application from S3 onto the server.  
 
Finally, you’ll clean up all the AWS resources to avoid unnecessary charges.  
 
Let’s get started and bring your project to life on AWS!

---

# 📂 Section 1: Set Up Networking in AWS

### 🎬 Intro Video
2. In this section, you’ll learn how to build a secure custom VPC from scratch. We’ll create public and private subnets, attach an Internet Gateway, set up a NAT Gateway, configure route tables, and understand the difference between public and private subnets in AWS.

### ✅ Video List
3. How to Create a Custom VPC in AWS
4. How to Create and Attach an Internet Gateway to Your VPC
5. How to Create Subnets in AWS
6. How to Make a Subnet Public in AWS (Route Table + Internet Gateway)
7. AWS Main Route Table — Explained
8. How to Create a NAT Gateway in AWS
9. How to Make a Subnet Private in AWS (Route Table + Nat Gateway)

---

# 📂 Section 2: Upload and Secure Application Code in S3

### 🎬 Intro Video
10. In this section, we’ll set up an S3 bucket to store the HTML application code and create an IAM role that gives our EC2 instance secure read access to that bucket.

### ✅ Video List
11. How to Create an S3 Bucket and Upload Application Code
12. How to Create an IAM Role to Access S3 from EC2

---

# 📂 Section 3: Launch and Connect to the EC2 Instance

### 🎬 Intro Video
13. In this section, we’ll generate an SSH key pair, move the private key to the home directory for both Windows and Mac users, create a security group to allow SSH and HTTP traffic, and launch an EC2 instance using the correct configuration.

### ✅ Video List
14. How to Create an SSH Key Pair in AWS
15. How to Move SSH Private Key to Home Directory (Windows)
16. How to Move SSH Private Key to Home Directory (Mac)
17. How to Create a Security Group and Open Ports for SSH and HTTP
18. How to Launch an EC2 Instance in AWS
19. How to SSH into an EC2 Instance Using a Private Key

---

# 📂 Section 4: Deploy and Host the HTML Application

### 🎬 Intro Video
20. In this section, we’ll explain the commands used to download and install the HTML application from S3 onto the EC2 instance, and serve it over the internet using Apache.

### ✅ Video List
21. HTML Deployment Script — Explained
22. How to Install and Host an HTML Application on EC2 with Apache

---

# 📂 Section 5: Clean Up AWS Resources

### 🎬 Intro Video
23. In this final section, we’ll delete the EC2 instance, security group, and other AWS resources to avoid ongoing costs after completing the project.

### ✅ Video List
24. How to Clean Up AWS Resources After Project Completion
