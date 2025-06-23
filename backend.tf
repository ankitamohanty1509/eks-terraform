terraform {
  backend "s3" {
    bucket         = "ankbuckectterraform"
    key            = "prod/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
  }
}
