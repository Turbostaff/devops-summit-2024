provider "aws" {
  region = "us-east-1"
}

resource "aws_kms_key" "s3_kms_key" {
  description = "KMS key for S3 bucket encryption"
  policy      = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "AWS": "*" },
      "Action": "kms:*",
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_s3_bucket" "my_bucket" {
  bucket = "my-aws-summit-2024-website"
  acl    = "private"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3_kms_key.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  website {
    index_document = "index.html"
  }

  logging {
    target_bucket = aws_s3_bucket.log_bucket.id
    target_prefix = "log/"
  }

  versioning {
    enabled = true
  }

  lifecycle_rule {
    id      = "expire-old-objects"
    enabled = true

    expiration {
      days = 365
    }
  }

  replication_configuration {
    role = aws_iam_role.replication.arn

    rules {
      id     = "replication-rule"
      status = "Enabled"

      destination {
        bucket        = aws_s3_bucket.replica.id
        storage_class = "STANDARD"
      }
    }
  }
}

resource "aws_s3_bucket" "log_bucket" {
  bucket = "my-aws-summit-2024-website-logs"
  acl    = "log-delivery-write"
}

resource "aws_s3_bucket" "replica" {
  bucket = "my-aws-summit-2024-website-replica"
  region = "us-west-1"
  acl    = "private"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3_kms_key.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

resource "aws_iam_role" "replication" {
  name = "s3-replication-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_s3_bucket_object" "index" {
  bucket                  = aws_s3_bucket.my_bucket.id
  key                     = "index.html"
  content_type            = "text/html"
  content                 = "Hello AWS Summit 2024"
  acl                     = "public-read"
  server_side_encryption  = "aws:kms"
  kms_key_id              = aws_kms_key.s3_kms_key.arn
}

resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for AWS Summit 2024 Website"
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.my_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "s3:GetObject"
        Effect    = "Allow"
        Resource  = "${aws_s3_bucket.my_bucket.arn}/*"
        Principal = {"AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity ${aws_cloudfront_origin_access_identity.oai.id}"}
      },
    ]
  })
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.my_bucket.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.my_bucket.id}"

    s3_origin_config {
      origin_access_identity = "origin-access-identity/cloudfront/${aws_cloudfront_origin_access_identity.oai.id}"
    }
  }

  enabled = true
  is_ipv6_enabled = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.my_bucket.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_All"

  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn            = "<your-acm-certificate-arn>"
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2018"
  }

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.log_bucket.bucket_domain_name
    prefix          = "cf-logs/"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

}
