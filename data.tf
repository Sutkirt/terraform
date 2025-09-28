data "aws_ami" "ecs_optimized" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["591542846629"]
}

data "aws_instance" "foo" {
  depends_on = [aws_autoscaling_group.bar]

  filter {
    name   = "tag:application"
    values = ["nexus"]
  }
}

output "instanceid" {
  value = data.aws_instance.foo.id

}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default_sub" {
  filter{
    name="vpc-id"
    values=[data.aws_vpc.default.id]
  }
}
data "aws_security_group" "default" {
  filter{
    name="vpc-id"
    values=[data.aws_vpc.default.id]
  }
  filter{
    name="group-name"
    values=["default"]
  }
}


data "aws_iam_role" "role"{
  name = "demo-ecs_role"
}