provider "aws" {
  region = "us-west-2"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t3.micro"
  type        = string
}

resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = var.instance_type

  tags = {
    Name = "WebServer"
    Env  = "production"
  }
}

output "instance_id" {
  value       = aws_instance.web.id
  description = "The instance ID"
}
