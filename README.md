
# Application load balancer with s3 bucket-access logs using Terraform

Elastic Load Balancing provides access logs that capture detailed information about requests sent to your load balancer. Each log contains information such as the time the request was received, the client's IP address, latencies, request paths, and server responses.

Here is a simple document to set up an s3 bucket-access logs for ALB using terraform
## Terraform Features

- The human-readable configuration language helps you write infrastructure code quickly.
- Friendly custom syntax, but also has support for JSON.
- AWS informations are defined using tfvars file and can easily changed
## Terraform Installation

- Create an IAM user on your AWS console that has "Access key - Programmatic access" with the policy permission of the required resource.
- Download Terraform, click here [Terraform](https://www.terraform.io/downloads)
-  Install Terraform,
 Use the following command to install Terraform

 ```bash
 $ wget https://releases.hashicorp.com/terraform/1.1.7/terraform_1.1.7_linux_amd64.zip
 $ unzip terraform_1.1.7_linux_amd64.zip 
 $ ll
 total 80136
 -rwxr-xr-x 1 ec2-user ec2-user 63262720 Mar  2 19:17 terraform
 -rw-rw-r-- 1 ec2-user ec2-user 18795309 Mar  2 19:32 terraform_1.1.7_linux_amd64.zip
$ sudo mv terraform /usr/local/bin/
$ terraform version
 Terraform v1.1.7
 on linux_amd64
```

**Create project Directory**

```bash
$ mkdir myproject
$ cd myproject/
```
**Lets create a file for declaring the variables.**

Input variables let you customize aspects of Terraform modules without altering the module's own source code. This allows you to share modules across different Terraform configurations, making your module composable and reusable.

 > Note : The terrafom files must be created with .tf extension. 

 ```bash
$ vim variable.tf
```
then, declare the variables for initialising terraform 
```bash
variable "region" {}
variable "access_key" {}
variable "secret_key" {}
variable "project_name" {}
variable "block" {}
variable "subnet" {}
```
**Create the provider file**

A provider is a Terraform plugin that allows users to manage an external API. Provider plugins like the AWS provider or the cloud-init provider act as a translation layer that allows Terraform to communicate with many different cloud providers, databases, and services.

```bash
$ vim provider.tf

 provider "aws" {
  region     = var.region
  access_key = var.access_key
  secret_key = var.secret_key
 }
```
**Create a terraform.tfvars**

 A terraform. tfvars file is used to set the actual values of the variables.

```bash
 $ vim terraform.tfvars

 region = "Desired region"
 access_key = "IAM user access_key"
 secret_key = "IAM user secret_key"
 project_name = " Your project name"
 block = "VPC cidr block"
 subnet = "3"
```
The Basic configuration for terraform aws is completed. Here I'm going to create the Application load balancer on an already created VPC. Therefore I'm using Terraform Module here.

Click here, [How to set up VPC on AWS using Terraform](https://github.com/radin-lawrence/Set-up-VPC)
> Note: Module allows you to group resources together and reuse this group later, possibly many times.


```bash
$ vim main.tf

 module "one" {
   source   = "/home/ec2-user/var/terraform/vpc/"
   cidr_blk = var.block
   project = var.project_name 
   region     = var.region
   access_key = var.access_key
   secret_key = var.secret_key
   subnet    = var.subnet
  } 
  ```

Now we need to initialize the terraform using the loaded values.
```bash
$ terraform init
```



## Creating Application Load Balancer

A load balancer serves as the single point of contact for clients. The load balancer distributes incoming application traffic across multiple targets, such as EC2 instances, in multiple Availability Zones.

**Create a security group for load balancer**

```bash
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

```
**Create TargetGroup For Application LoadBalancer**

Create a new target group for the application load balancer. Traffic will be routed to target web server instances on HTTP port 80. We will also define a health check for targets.
```bash
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
```
> create_before_destroy - This flag is used to ensure the replacement of a resource is created before the original instance is destroyed

**Create Application LoadBalancer**

```bash
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
```

**Create S3 bucket to store the access logs of ALB**

Elastic Load Balancing provides access logs that capture detailed information about requests sent to your load balancer. Each log contains information such as the time the request was received, the client's IP address, latencies, request paths, and server responses. You can use these access logs to analyze traffic patterns and troubleshoot issues.
```bash
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

```

**Setup the S3 bucket policy**

```bash
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

```
**Creating http listener of application loadbalancer with default action**

The listener is configured to accept HTTP client connections.
```bash
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

```
**Set up listener rule**

Provides a Load Balancer Listener Rule resource.
```bash
resource "aws_lb_listener_rule" "static" {
  listener_arn = aws_lb_listener.front_end.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target1.arn
  }

  condition {
    host_header {
      values = ["<host-name>"]
    }
  }
}
```

Please enter the <host-name> you would like to forward.

Next, we need to create Launch configuration so that we can create Auto scaling group

**Launch Configuration**

 We are using file() to load user data.

```bash
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
```

**Create Auto Scaling Group**

```bash
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
  wait_for_elb_capacity     = 2

tag {
    key                 = "Name"
    value               = var.project_name
    propagate_at_launch = true
  }
    
  lifecycle {
    create_before_destroy = true
  }
}
```

We need to create user data for launch configuration.

```bash
$ vim script.sh

#!/bin/bash

echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config
echo "LANG=en_US.utf-8" >> /etc/environment
echo "LC_ALL=en_US.utf-8" >> /etc/environment

echo "password@123" | passwd root --stdin
sed  -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
service sshd restart

yum install httpd php -y

cat <<EOF > /var/www/html/index.php
<?php
\$output = shell_exec('echo $HOSTNAME');
echo "<h1><center><pre>\$output</pre></center></h1>";
echo "<h1><center> Terraform with ALB and S3 </center></h1>"
?>
EOF

service httpd restart
chkconfig httpd on

```

**Terraform Validation**

This will check for any errors on the source code

```bash
terrafom validate
```

**Terraform Plan**

Creates an execution plan, which lets you preview the changes that Terraform plans to make to your infrastructure.
```bash
terraform plan -var-file="variable.tfvars"
```

**Terraform apply**

Executes the actions proposed in a Terraform plan.
```bash
terraform apply -var-file="variable.tfvars"
```




## Conclusion
Here is a simple document on how to use Terraform to  set up s3 bucket-access logs for ALB using terraform

  
 ### ⚙️ Connect with Me
<p align="center">
<a href="https://www.linkedin.com/in/radin-lawrence-8b3270102/"><img src="https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white"/></a>
<a href="mailto:radin.lawrence@gmail.com"><img src="https://img.shields.io/badge/Gmail-D14836?style=for-the-badge&logo=gmail&logoColor=white"/></a>
