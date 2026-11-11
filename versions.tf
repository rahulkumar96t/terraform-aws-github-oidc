terraform {
  # 1.9 is the first release whose variable validations may reference other
  # variables (used to cross-check the provider inputs and the wildcard guard).
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
