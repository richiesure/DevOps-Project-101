locals {
  name = var.project_name
  tags = {
    Project = var.project_name
    Managed = "terraform"
  }
}

# -------------------------
# Networking (single AZ)
# -------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = merge(local.tags, { Name = "${local.name}-vpc" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.tags, { Name = "${local.name}-igw" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.az
  map_public_ip_on_launch = true
  tags = merge(local.tags, { Name = "${local.name}-public" })
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.az
  tags = merge(local.tags, { Name = "${local.name}-private" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.tags, { Name = "${local.name}-rt-public" })
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# NAT for private instances to reach internet (pull Docker from ECR)
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${local.name}-nat-eip" })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = merge(local.tags, { Name = "${local.name}-nat" })
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.tags, { Name = "${local.name}-rt-private" })
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# -------------------------
# Security Groups
# -------------------------
# ALB SG: allow HTTP from world (for now)
resource "aws_security_group" "alb_sg" {
  name        = "${local.name}-alb-sg"
  description = "ALB security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.alb_allowed_cidr
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-alb-sg" })
}

# App SG: allow 8080 from ALB only
resource "aws_security_group" "app_sg" {
  name        = "${local.name}-app-sg"
  description = "App instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # SSM, ECR, package repos via NAT -> outbound open
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-app-sg" })
}

# DB SG: allow 3306 from App only
resource "aws_security_group" "db_sg" {
  name        = "${local.name}-db-sg"
  description = "DB access from app"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from app"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-db-sg" })
}

# -------------------------
# ECR repository
# -------------------------
resource "aws_ecr_repository" "app" {
  name                 = "${local.name}"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = local.tags
}

# -------------------------
# RDS (single AZ)
# -------------------------
resource "aws_db_subnet_group" "db" {
  name       = "${local.name}-db-subnet"
  subnet_ids = [aws_subnet.private.id] # single-AZ as requested
  tags       = local.tags
}

resource "random_password" "db_password" {
  length  = 20
  special = true
}

# Store username/password in Secrets Manager
resource "aws_secretsmanager_secret" "db" {
  name = "${local.name}/db"
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "db_v" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
  })
}

resource "aws_db_instance" "app_db" {
  identifier                = "${local.name}-db"
  allocated_storage         = 20
  engine                    = var.db_engine
  engine_version            = var.db_engine_version
  instance_class            = var.db_instance_class
  db_name                   = var.db_name
  username                  = var.db_username
  password                  = random_password.db_password.result
  db_subnet_group_name      = aws_db_subnet_group.db.name
  vpc_security_group_ids    = [aws_security_group.db_sg.id]
  publicly_accessible       = false
  skip_final_snapshot       = true
  deletion_protection       = false
  multi_az                  = false  # you asked for single AZ
  storage_encrypted         = true
  backup_retention_period   = 7
  tags                      = local.tags
}

# -------------------------
# IAM for App instances (ECR + Secrets + SSM)
# -------------------------
data "aws_iam_policy_document" "app_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service" identifiers = ["ec2.amazonaws.com"] }
  }
}

resource "aws_iam_role" "app_role" {
  name               = "${local.name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.app_assume.json
  tags               = local.tags
}

# Managed policies for SSM & ECR read
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "ecr" {
  role       = aws_iam_role.app_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Inline policy to read DB secret
data "aws_iam_policy_document" "app_inline" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db.arn]
  }
}
resource "aws_iam_role_policy" "app_secret_read" {
  name   = "${local.name}-secret-read"
  role   = aws_iam_role.app_role.id
  policy = data.aws_iam_policy_document.app_inline.json
}

resource "aws_iam_instance_profile" "app_profile" {
  name = "${local.name}-instance-profile"
  role = aws_iam_role.app_role.name
}

# -------------------------
# Launch Template + Auto Scaling (private subnet)
# -------------------------
data "aws_ssm_parameter" "al2023_ami" {
  # Latest Amazon Linux 2023 AMI
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

data "template_file" "user_data" {
  template = file("${path.module}/user_data_app.sh")
  vars = {
    ecr_repo        = aws_ecr_repository.app.repository_url
    app_image_tag   = var.app_image_tag
    db_secret_name  = aws_secretsmanager_secret.db.name
    db_host         = aws_db_instance.app_db.address
    db_name         = var.db_name
    db_username     = var.db_username
  }
}

resource "aws_launch_template" "app_lt" {
  name_prefix   = "${local.name}-lt-"
  image_id      = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.app_instance_type
  key_name      = var.key_pair_name != "" ? var.key_pair_name : null

  iam_instance_profile { name = aws_iam_instance_profile.app_profile.name }

  network_interfaces {
    security_groups = [aws_security_group.app_sg.id]
  }

  user_data = base64encode(data.template_file.user_data.rendered)

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name}-app" })
  }
}

resource "aws_autoscaling_group" "app_asg" {
  name                = "${local.name}-asg"
  vpc_zone_identifier = [aws_subnet.private.id]
  desired_capacity    = var.app_desired_size
  min_size            = var.app_min_size
  max_size            = var.app_max_size

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 120

  tag {
    key                 = "Name"
    value               = "${local.name}-app"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Target group for HTTP:8080
resource "aws_lb_target_group" "app_tg" {
  name        = "${local.name}-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"
  health_check {
    path                = "/actuator/health"
    port                = "8080"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 20
    matcher             = "200-399"
  }
  tags = local.tags
}

# Attach ASG -> TG
resource "aws_autoscaling_attachment" "asg_tg" {
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  lb_target_group_arn    = aws_lb_target_group.app_tg.arn
}

# Internet-facing ALB in public subnet
resource "aws_lb" "app_alb" {
  name               = "${local.name}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public.id]
  idle_timeout       = 60
  tags               = local.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}
