terraform {
  backend "s3" {
    bucket         = "235494811179"
    key            = "prod/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
  }
}
