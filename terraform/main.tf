########################################
# Terraform + AWS Provider
########################################
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

########################################
# Variables
########################################
variable "project" {
  description = "Project codename"
  type        = string
  default     = "ecommerce"
}

variable "bucket_name" {
  description = "S3 bucket for the data lake"
  type        = string
  default     = "serrabits-bucket"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# Optional: allow overriding the pre-existing role name if needed
variable "existing_glue_role_name" {
  description = "Existing IAM role to be used by Glue crawlers/jobs"
  type        = string
  default     = "LabRole"
}

########################################
# S3 Data Lake Bucket
########################################
resource "aws_s3_bucket" "lake" {
  bucket = var.bucket_name

  tags = {
    Project = var.project
    Layer   = "datalake"
  }
}

resource "aws_s3_bucket_versioning" "lake" {
  bucket = aws_s3_bucket.lake.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "lake" {
  bucket                  = aws_s3_bucket.lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Medallion prefixes + Athena results
locals {
  base_prefixes = [
    "bronze/", "bronze/ecommerce/", "bronze/ecommerce/customers/", "bronze/ecommerce/products/",
    "bronze/ecommerce/orders/", "bronze/ecommerce/order_items/",
    "silver/", "silver/ecommerce/", "silver/ecommerce/customers/", "silver/ecommerce/products/",
    "silver/ecommerce/orders/", "silver/ecommerce/order_items/",
    "gold/", "gold/ecommerce/", "gold/ecommerce/dim_customer/", "gold/ecommerce/dim_product/",
    "gold/ecommerce/fact_orders/", "gold/ecommerce/fact_order_items/",
    "athena/"
  ]
}

resource "aws_s3_object" "folders" {
  for_each = toset(local.base_prefixes)
  bucket   = aws_s3_bucket.lake.id
  key      = each.key
  content  = ""
}

# --- Access logging target bucket ---
resource "aws_s3_bucket" "lake_logs" {
  bucket = "${var.bucket_name}-logs"
  tags   = { Project = var.project, Layer = "logs" }
}

resource "aws_s3_bucket_public_access_block" "lake_logs" {
  bucket                  = aws_s3_bucket.lake_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 requires ownership controls before setting ACLs
resource "aws_s3_bucket_ownership_controls" "lake_logs" {
  bucket = aws_s3_bucket.lake_logs.id
  rule { object_ownership = "BucketOwnerPreferred" }
}

# Allow S3 log delivery to write into the logs bucket
resource "aws_s3_bucket_acl" "lake_logs" {
  bucket     = aws_s3_bucket.lake_logs.id
  acl        = "log-delivery-write"
  depends_on = [aws_s3_bucket_ownership_controls.lake_logs]
}

# Enable server access logging on the main bucket
resource "aws_s3_bucket_logging" "lake" {
  bucket        = aws_s3_bucket.lake.id
  target_bucket = aws_s3_bucket.lake_logs.id
  target_prefix = "lake/"
}

# Customer-managed KMS key for S3 encryption
resource "aws_kms_key" "datalake" {
  description         = "KMS key for S3 Data Lake encryption"
  enable_key_rotation = true
  tags = { Project = var.project, Layer = "datalake" }
}

# Default encryption for MAIN bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.datalake.arn
    }
  }
}

# Versioning for LOGS bucket (tfsec flagged this)
resource "aws_s3_bucket_versioning" "lake_logs" {
  bucket = aws_s3_bucket.lake_logs.id
  versioning_configuration { status = "Enabled" }
}

# Default encryption for LOGS bucket too (best practice & clears encryption finding)
resource "aws_s3_bucket_server_side_encryption_configuration" "lake_logs" {
  bucket = aws_s3_bucket.lake_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.datalake.arn
    }
  }
}


########################################
# IAM (USE EXISTING ROLE)
########################################
# Reuse the pre-existing role (no creation/attachments here)
data "aws_iam_role" "glue_role" {
  name = var.existing_glue_role_name
}

########################################
# Glue Data Catalog + Crawlers (BRONZE)
########################################
resource "aws_glue_catalog_database" "db" {
  name = var.project
  tags = { Project = var.project, Layer = "catalog" }
}

locals {
  crawler_targets = {
    customers   = "s3://${var.bucket_name}/bronze/ecommerce/customers/"
    products    = "s3://${var.bucket_name}/bronze/ecommerce/products/"
    orders      = "s3://${var.bucket_name}/bronze/ecommerce/orders/"
    order_items = "s3://${var.bucket_name}/bronze/ecommerce/order_items/"
  }
}

resource "aws_glue_crawler" "bronze_crawlers" {
  for_each      = local.crawler_targets
  name          = "${var.project}-bronze-${each.key}"
  role          = data.aws_iam_role.glue_role.arn # <— use LabRole
  database_name = aws_glue_catalog_database.db.name
  table_prefix  = "bronze_" # remove if you don't want a prefix

  s3_target { path = each.value }

  recrawl_policy { recrawl_behavior = "CRAWL_EVERYTHING" }
  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  tags = { Project = var.project, Layer = "bronze" }
}

########################################
# Athena Workgroup (results -> s3://.../athena/)
########################################
resource "aws_athena_workgroup" "wg" {
  name = "${var.project}-wg"

  configuration {
    enforce_workgroup_configuration = true
    result_configuration {
      output_location = "s3://${aws_s3_bucket.lake.bucket}/athena/"
    }
  }

  tags = { Project = var.project }
}

########################################
# Outputs
########################################
output "bucket_name" { value = aws_s3_bucket.lake.bucket }
output "glue_database" { value = aws_glue_catalog_database.db.name }
output "glue_crawlers" { value = [for c in aws_glue_crawler.bronze_crawlers : c.name] }
output "athena_workgroup" { value = aws_athena_workgroup.wg.name }
output "glue_role_used" { value = data.aws_iam_role.glue_role.arn }



