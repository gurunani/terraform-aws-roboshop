resource "aws_lb_target_group" "main" {
  name     = "${var.project}-${var.environment}-${var.component}"
  port     = local.tg_port
  protocol = "HTTP"
  vpc_id   = local.vpc_id
  deregistration_delay = 60
  
  health_check {
    healthy_threshold   = 2
    interval            = 15
    matcher             = "200-299"
    path                = local.health_check_path
    port                = local.tg_port
    timeout             = 5
    unhealthy_threshold = 3
  }
}

# Listener Rule to route traffic to component
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

# Provision component instance
resource "terraform_data" "main" {
  triggers_replace = [
    aws_instance.main.id
  ]
  
  provisioner "file" {
    source      = "bootstrap.sh"
    destination = "/tmp/${var.component}.sh"

    connection {
      type     = "ssh"
      user     = "ec2-user"
      password = "DevOps321"
      host     = aws_instance.main.private_ip
      timeout  = "5m"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/${var.component}.sh",
      "sudo sh /tmp/${var.component}.sh ${var.component} ${var.environment}"
    ]

    connection {
      type     = "ssh"
      user     = "ec2-user"
      password = "DevOps321"
      host     = aws_instance.main.private_ip
      timeout  = "5m"
    }
  }
}

# Stop instance to create AMI
resource "aws_ec2_instance_state" "main" {
  instance_id = aws_instance.main.id
  state       = "stopped"
  depends_on  = [terraform_data.main]
}

# Create AMI from the configured instance
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

# Terminate the instance after AMI creation
resource "terraform_data" "main_delete" {
  triggers_replace = [
    aws_ami_from_instance.main.id
  ]
  
  provisioner "local-exec" {
    command = "aws ec2 terminate-instances --instance-ids ${aws_instance.main.id}"
  }

  depends_on = [aws_ami_from_instance.main]
}

# Launch Template for Auto Scaling
resource "aws_launch_template" "main" {
  name_prefix = "${var.project}-${var.environment}-${var.component}-"

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
  
  depends_on = [terraform_data.main_delete]
}

# Auto Scaling Group
resource "aws_autoscaling_group" "main" {
  name_prefix         = "${var.project}-${var.environment}-${var.component}-"
  vpc_zone_identifier = local.private_subnet_ids
  desired_capacity    = 2
  max_size            = 4
  min_size            = 2
  health_check_type   = "ELB"
  health_check_grace_period = 120
  target_group_arns   = [aws_lb_target_group.main.arn]

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-${var.environment}-${var.component}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  depends_on = [aws_launch_template.main]
}

# Auto Scaling Policy - Scale Up
resource "aws_autoscaling_policy" "main_scale_up" {
  name                   = "${var.project}-${var.environment}-${var.component}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 120
  autoscaling_group_name = aws_autoscaling_group.main.name
}

# Auto Scaling Policy - Scale Down
resource "aws_autoscaling_policy" "main_scale_down" {
  name                   = "${var.project}-${var.environment}-${var.component}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 120
  autoscaling_group_name = aws_autoscaling_group.main.name
}

# CloudWatch Alarm - High CPU
resource "aws_cloudwatch_metric_alarm" "main_cpu_high" {
  alarm_name          = "${var.project}-${var.environment}-${var.component}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  alarm_actions = [aws_autoscaling_policy.main_scale_up.arn]
}

# CloudWatch Alarm - Low CPU
resource "aws_cloudwatch_metric_alarm" "main_cpu_low" {
  alarm_name          = "${var.project}-${var.environment}-${var.component}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 30

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  alarm_actions = [aws_autoscaling_policy.main_scale_down.arn]
}