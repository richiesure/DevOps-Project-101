provider "aws" {
  region = "eu-west-2"
}

# --------------------------
# Fetch latest Amazon Linux AMI
# --------------------------
data "aws_ami" "latest_amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# --------------------------
# VPC
# --------------------------
resource "aws_vpc" "app_vpc" {
  cidr_block = "10.1.0.0/16"

  tags = {
    Name = "java-login-app-vpc-v2"
  }
}

# --------------------------
# Subnets
# --------------------------
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.app_vpc.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-a-v2"
  }
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.app_vpc.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-b-v2"
  }
}

# --------------------------
# Internet Gateway
# --------------------------
resource "aws_internet_gateway" "app_igw" {
  vpc_id = aws_vpc.app_vpc.id

  tags = {
    Name = "java-login-app-igw-v2"
  }
}

# --------------------------
# Route Table
# --------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.app_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app_igw.id
  }

  tags = {
    Name = "public-rt-v2"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

# --------------------------
# Security Groups
# --------------------------
resource "aws_security_group" "alb_sg" {
  name        = "java-login-app-alb-sg-v2"
  description = "Allow HTTP traffic to ALB"
  vpc_id      = aws_vpc.app_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "java-login-app-alb-sg-v2"
  }
}

resource "aws_security_group" "app_sg" {
  name        = "java-login-app-app-sg-v2"
  description = "Allow HTTP traffic to app instances"
  vpc_id      = aws_vpc.app_vpc.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "java-login-app-app-sg-v2"
  }
}

# --------------------------
# Load Balancer
# --------------------------
resource "aws_lb" "app_alb" {
  name               = "java-login-app-alb-v2"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]

  tags = {
    Name = "java-login-app-alb-v2"
  }
}

resource "aws_lb_target_group" "app_tg" {
  name     = "java-login-app-tg-v2"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.app_vpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name = "java-login-app-tg-v2"
  }
}

resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# --------------------------
# Launch Template
# --------------------------
resource "aws_launch_template" "app_lt" {
  name_prefix   = "java-login-app-lt-v2"
  image_id      = data.aws_ami.latest_amazon_linux.id
  instance_type = "t2.micro"

  key_name = "Farm"  # <--- remove .pem

  user_data = base64encode(file("${path.module}/scripts/user-data-template.sh"))

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app_sg.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "java-login-app-instance-v2"
    }
  }
}

# --------------------------
# Auto Scaling Group
# --------------------------
resource "aws_autoscaling_group" "app_asg" {
  name                = "java-login-app-asg-v2"
  max_size            = 2
  min_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app_tg.arn]

  tag {
    key                 = "Name"
    value               = "java-login-app-instance-v2"
    propagate_at_launch = true
  }
}

# --------------------------
# Outputs
# --------------------------
output "alb_dns_name" {
  value = aws_lb.app_alb.dns_name
}

output "app_asg_name" {
  value = aws_autoscaling_group.app_asg.name
}

output "vpc_id" {
  value = aws_vpc.app_vpc.id
}
