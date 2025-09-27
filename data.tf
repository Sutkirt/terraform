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
