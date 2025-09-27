resource "aws_efs_file_system" "nexus" {
  creation_token = "nexus-efs"
  encrypted      = true
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  tags = {
    Name = "nexus-efs"
  }
}

resource "aws_efs_mount_target" "nexus_az1" {
  file_system_id  = aws_efs_file_system.nexus.id
  subnet_id       = "subnet-00f1be2cc61fe155c"
  security_groups = ["sg-09f4b4a5801b31185"]
}

resource "aws_efs_mount_target" "nexus_az2" {
  file_system_id  = aws_efs_file_system.nexus.id
  subnet_id       = "subnet-0ca792222c939242e"
  security_groups = ["sg-09f4b4a5801b31185"]
}

resource "aws_efs_access_point" "nexus_data" {
  file_system_id = aws_efs_file_system.nexus.id

  posix_user {
    uid = 200
    gid = 200
  }

  root_directory {
    path = "/data"
    creation_info {
      owner_gid   = 200
      owner_uid   = 200
      permissions = "770"
    }
  }
}

resource "aws_efs_access_point" "nexus_logs" {
  file_system_id = aws_efs_file_system.nexus.id

  posix_user {
    uid = 200
    gid = 200
  }

  root_directory {
    path = "/logs"
    creation_info {
      owner_gid   = 200
      owner_uid   = 200
      permissions = "770"
    }
  }
}

resource "aws_iam_instance_profile" "instance-profile" {
  name = "demo-instance_profile"
  role = aws_iam_role.role.name
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "role" {
  name                = "demo-ecs_role"
  path                = "/"
  assume_role_policy  = data.aws_iam_policy_document.assume_role.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role", "arn:aws:iam::aws:policy/AmazonElasticFileSystemClientReadWriteAccess", "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore", "arn:aws:iam::aws:policy/AdministratorAccess"]
}


resource "aws_ecs_cluster" "tst-cluster" {
  name = "demo-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_launch_template" "foobar" {
  name_prefix   = "test-lt"
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = "t2.large"
  iam_instance_profile {
    name = aws_iam_instance_profile.instance-profile.name
  }
  user_data = filebase64("${path.module}/user_data.sh")
   tag_specifications {
    resource_type = "instance"

    tags = {
      application = "nexus"
      Environment = "dev"
    }
  }
}

resource "aws_autoscaling_group" "bar" {
  depends_on         = [aws_launch_template.foobar]
  availability_zones = ["us-west-1a"]
  desired_capacity   = 1
  max_size           = 1
  min_size           = 1

  launch_template {
    id      = aws_launch_template.foobar.id
    version = "$Latest"
  }
}

resource "aws_ecs_task_definition" "nexus" {
  family                   = "nexus-tdef"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  cpu                      = "1524"
  memory                   = "4048"
  execution_role_arn       = "arn:aws:iam::296352766082:role/ecsTaskExecutionRole"
  task_role_arn            = "arn:aws:iam::296352766082:role/ecsTaskExecutionRole"

  container_definitions = jsonencode([
    {
      name      = "nexus"
      image     = "sonatype/nexus:pro-2.15.2-03"
      essential = true
      cpu       = 1524
      memory    = 4048

      portMappings = [
        {
          containerPort = 8081
          hostPort      = 8081
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "nexus-efs-data"
          containerPath = "/opt/nexus/data"
          readOnly      = false
        },
        {
          sourceVolume  = "nexus-efs-logs"
          containerPath = "/opt/nexus/logs"
          readOnly      = false
        }
      ]
    }
  ])

  volume {
    name = "nexus-efs-data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.nexus.id
      root_directory     = "/"
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.nexus_data.id
        iam             = "DISABLED"
      }
    }
  }

  volume {
    name = "nexus-efs-logs"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.nexus.id
      root_directory     = "/"
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.nexus_logs.id
        iam             = "DISABLED"
      }
    }
  }
}

resource "aws_ecs_service" "demo-service" {
  depends_on = [
    aws_iam_role_policy_attachment.ecs_service_role_attach,
    aws_lb_target_group.nexus,
    aws_lb_listener.http
  ]
  name            = "nexus-service"
  cluster         = aws_ecs_cluster.tst-cluster.id
  task_definition = aws_ecs_task_definition.nexus.arn
  desired_count   = 1
  load_balancer {
    target_group_arn = aws_lb_target_group.nexus.arn
    container_name   = "nexus"
    container_port   = 8081
  }
  iam_role = aws_iam_role.ecs_service_role.arn
}

resource "aws_lb" "nexus" {
  name               = "${terraform.workspace}-nexus"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["sg-09f4b4a5801b31185"]
  subnets            = ["subnet-0ca792222c939242e", "subnet-00f1be2cc61fe155c"]

  enable_deletion_protection = false

  tags = {
    Environment = "Development"
    Project     = "Example"
  }
}

resource "aws_lb_target_group" "nexus" {
  name_prefix = "h1"
  port        = 8081
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = "vpc-00f2a9392ffd68490"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Environment = "Development"
    Project     = "Example"
  }
}

resource "aws_lb_listener" "http" {
  depends_on = [aws_lb_target_group.nexus] 
  load_balancer_arn = aws_lb.nexus.arn
  port              = 8081
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nexus.arn
  }
}

resource "aws_iam_role" "ecs_service_role" {
  name = "ecsServiceRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_service_role_attach" {
  role       = aws_iam_role.ecs_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

