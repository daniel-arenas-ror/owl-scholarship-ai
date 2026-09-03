terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Remote state. Create the bucket + DynamoDB lock table once by hand
  # (see README), then uncomment and run `terraform init -migrate-state`.
  #
  # backend "s3" {
  #   bucket         = "owl-tfstate-<your-account-id>"
  #   key            = "owl/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "owl-tfstate-lock"
  #   encrypt        = true
  # }
}
