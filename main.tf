provider "aws" {
  region = "eu-west-1"
}

resource "aws_s3_bucket" "my_bucket" {
  bucket = "reply-devops-summit-2024" # Bucket names must be unique across all AWS users
  acl    = "private" # Defines who can access the bucket. Options include: private, public-read, public-read-write, aws-exec-read, authenticated-read, and log-delivery-write.
}
