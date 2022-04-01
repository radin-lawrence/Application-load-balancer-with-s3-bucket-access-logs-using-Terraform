

module "one" {
  source = "/home/ec2-user/var/terraform/vpc/"
  cidr_blk = var.block
  project = var.project_name 
  region     = var.region
  access_key = var.access_key
  secret_key = var.secret_key
  subnet    = var.subnet
}


resource "aws_security_group" "free" {
  name        = "free"
  description = "Allow 22,80,443"
  vpc_id      = module.one.my_vpc

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

 ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

 ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.project_name}-free"
  }
}

resource "aws_lb_target_group" "target1" {
  name_prefix    = "${substr(var.project_name,0,4)}-t"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.one.my_vpc


health_check{
  healthy_threshold = 2
  unhealthy_threshold = 2
  interval = 15
  path = "/"
  matcher = "200"
 }

lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "myalb" {
 name_prefix   =  "${substr(var.project_name,0,4)}-"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.free.id]
  subnets            = module.one.public

   enable_deletion_protection = false

  access_logs {
    bucket  = aws_s3_bucket.alb_log.bucket
    prefix  = "test-lb"
    enabled = true
  }

  tags = {
    Environment = "${var.project_name}-alb"
  }
lifecycle {
    create_before_destroy = true
  }
}


resource "aws_s3_bucket" "alb_log" {
  bucket = "my-log-test-bucket"

  tags = {
    Name        = "${var.project_name}log"
  }
}

resource "aws_s3_bucket_acl" "acl" {
  bucket = aws_s3_bucket.alb_log.id
  acl    = "private"
}

 
resource "aws_s3_bucket_policy" "policy" {
  bucket = aws_s3_bucket.alb_log.id
  policy = data.aws_iam_policy_document.s3_policy.json
}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
 effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = [
      aws_s3_bucket.alb_log.arn,
      "${aws_s3_bucket.alb_log.arn}/*",
    ]
  }
}


resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.myalb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Sorry!!! Does not exist."
      status_code  = "200"
    }
  }
}


resource "aws_lb_listener_rule" "static" {
  listener_arn = aws_lb_listener.front_end.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target1.arn
  }

  condition {
    host_header {
      values = ["${var.project_name}.radinlaw.tech"]
    }
  }
}


resource "aws_launch_configuration" "conf" {
  name_prefix   = "${substr(var.project_name,0,4)}-"
  image_id  = "ami-04893cdb768d0f9ee"
  instance_type = "t2.micro"
  security_groups  = [aws_security_group.free.id]
  user_data = file("script.sh")
  

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_autoscaling_group" "asg" {
  name_prefix               = "${var.project_name}-asg"
  launch_configuration      = aws_launch_configuration.conf.name
  vpc_zone_identifier       = module.one.public
  target_group_arns         = [aws_lb_target_group.target1.arn]
  max_size                  = 2
  min_size                  = 2
  health_check_grace_period = 120
  health_check_type         = "EC2"
  desired_capacity          = 2
  wait_for_elb_capacity =    2

tag {
    key                 = "Name"
    value               = var.project_name
    propagate_at_launch = true
  }
    
  lifecycle {
    create_before_destroy = true
  }
}



