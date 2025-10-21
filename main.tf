resource "aws_lb_target_group" "main" {
  name     = "${var.project}-${var.environment}-${var.component}"
  port     = local.tg_port
  protocol = "HTTP"
  vpc_id   = local.vpc_id
  deregistration_delay = 60  # Changed from 120 to match working version
  
  health_check {
    healthy_threshold   = 2
    interval            = 15  # Changed from 5 (too aggressive)
    matcher             = "200-299"
    path                = local.health_check_path
    port                = local.tg_port
    timeout             = 5   # Changed from 2 (too short)
    unhealthy_threshold = 3
  }
}

resource "aws_instance" "main" {
  ami                    = local.ami_id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [local.sg_id]
  subnet_id              = local.private_subnet_id
  
  tags = merge(
    local.common_tags,
    {
      Name = "${var.project}-${var.environment}-${var.component}"
    }
  )
}

resource "terraform_data" "main" {
  triggers_replace = [
    aws_instance.main.id
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    password = "DevOps321"
    host     = aws_instance.main.private_ip
    timeout  = "5m"
  }
  
  provisioner "file" {
    source      = "bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/bootstrap.sh",
      "sudo sh /tmp/bootstrap.sh ${var.component} ${var.environment}"
    ]
  }

  depends_on = [aws_instance.main]
}

resource "aws_ec2_instance_state" "main" {
  instance_id = aws_instance.main.id
  state       = "stopped"
  depends_on  = [terraform_data.main]
}

# CRITICAL FIX: Add timestamp to make AMI name unique
resource "aws_ami_from_instance" "main" {
  name               = "${var.project}-${var.environment}-${var.component}-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  source_instance_id = aws_instance.main.id
  depends_on         = [aws_ec2_instance_state.main]
  
  tags = merge(
    local.common_tags,
    {
      Name = "${var.project}-${var.environment}-${var.component}"
    }
  )
}

resource "terraform_data" "main_delete" {
  triggers_replace = [
    aws_ami_from_instance.main.id
  ]
  
  provisioner "local-exec" {
    command = "aws ec2 terminate-instances --instance-ids ${aws_instance.main.id}"
  }

  depends_on = [aws_ami_from_instance.main]
}

resource "aws_launch_template" "main" {
  name_prefix = "${var.project}-${var.environment}-${var.component}-"  # Changed to name_prefix for multiple versions

  image_id                             = aws_ami_from_instance.main.id
  instance_initiated_shutdown_behavior = "terminate"
  instance_type                        = "t3.micro"
  vpc_security_group_ids               = [local.sg_id]
  update_default_version               = true

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.common_tags,
      {
        Name = "${var.project}-${var.environment}-${var.component}"
      }
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      local.common_tags,
      {
        Name = "${var.project}-${var.environment}-${var.component}"
      }
    )
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project}-${var.environment}-${var.component}"
    }
  )

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [terraform_data.main_delete]
}

resource "aws_autoscaling_group" "main" {
  name_prefix          = "${var.project}-${var.environment}-${var.component}-"
  desired_capacity     = 2  # Changed from 1 to match working version
  max_size             = 4  # Changed from 10 to match working version
  min_size             = 2  # Changed from 1 to match working version
  target_group_arns    = [aws_lb_target_group.main.arn]
  vpc_zone_identifier  = local.private_subnet_ids
  health_check_grace_period = 120  # Increased from 90 for better stability
  health_check_type         = "ELB"

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = merge(
      local.common_tags,
      {
        Name = "${var.project}-${var.environment}-${var.component}"
      }
    )
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["launch_template"]
  }

  timeouts {
    delete = "15m"
  }

  depends_on = [aws_launch_template.main]
}

# Auto Scaling Policy - Target Tracking
resource "aws_autoscaling_policy" "main" {
  name                   = "${var.project}-${var.environment}-${var.component}"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "TargetTrackingScaling"
  
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0  # Changed from 75 to match working version threshold
  }
}

resource "aws_lb_listener_rule" "main" {
  listener_arn = local.alb_listener_arn
  priority     = var.rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  condition {
    host_header {
      values = [local.rule_header_url]
    }
  }
}