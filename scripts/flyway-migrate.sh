#!/bin/bash

# Define environment variables
export S3_URI=s3://aosnote-rentzone-sql-files/V1__rentzone-db.sql
export RDS_ENDPOINT=dev-rds-db.cu2idoemakwo.us-east-1.rds.amazonaws.com
export RDS_DB_NAME=applicationdb
export RDS_DB_USERNAME=azeezs
export RDS_DB_PASSWORD=azeezs123

# Update all packages
sudo yum update -y

# Download and extract Flyway
sudo wget -qO- https://download.red-gate.com/maven/release/com/redgate/flyway/flyway-commandline/11.2.0/flyway-commandline-11.2.0-linux-x64.tar.gz | tar -xvz && sudo ln -s `pwd`/flyway-11.2.0/flyway /usr/local/bin 

# Create the SQL directory for migrations
sudo mkdir sql

# Download the migration SQL script from AWS S3
sudo aws s3 cp "$S3_URI" sql/

# Run Flyway migration
sudo flyway -url=jdbc:mysql://"$RDS_ENDPOINT":3306/"$RDS_DB_NAME"?allowPublicKeyRetrieval=true \
  -user="$RDS_DB_USERNAME" \
  -password="$RDS_DB_PASSWORD" \
  -locations=filesystem:sql \
  migrate