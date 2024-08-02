terraform {
  backend "s3" {
    bucket         = "s3bu100"  # Replace with your bucket name
    key            = "terraform.tfstate"   # Path to the state file in the bucket
    region         = "us-east-1"                  # Change to your region
    dynamodb_table = "db01"            # For state locking
    access_key  = var.aws_access_key_id
    secret_key  = var.aws_secret_access_key
  }
}

provider "aws" {
  region     = "us-east-1"
  access_key  = var.aws_access_key_id
  secret_key  = var.aws_secret_access_key
}

resource "aws_security_group" "SG_i_22_80" {
  name        = "webserver access"
  description = "Allow webserver and console access"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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
}

resource "aws_subnet" "private" {
  vpc_id                  = "vpc-07ebbeb84822543e5"
  cidr_block              = "172.31.96.0/25"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false
}

resource "aws_instance" "Ngnix_LOAD_BALANCER" {
  ami           = "ami-0b72821e2f351e396"
  instance_type = "t2.medium"
  vpc_security_group_ids = [aws_security_group.SG_i_22_80.id]
  tags = {
    Name = "Ngnix_LB"
  }
  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "ssh-rsa 2048 SHA256:UbCOIKDTVxSWGqjEK5uFwuzrPapd994fluf0fDiBdnY" >> /home/ec2-user/.ssh/authorized_keys
              yum update -y
              amazon-linux-extras install -y nginx1
              yum install -y nginx
              cat <<EOT > /etc/nginx/conf.d/load_balancer.conf
              upstream backend {"yahoo.com"}
              server {
                  listen 80;
                  location / {
                      proxy_pass http://backend;
                      proxy_set_header Host \$host;
                      proxy_set_header X-Real-IP \$remote_addr;
                      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
                      proxy_set_header X-Forwarded-Proto \$scheme;
                  }
              }
              EOT
              systemctl start nginx
              systemctl enable nginx
              EOF
  )
}

resource "aws_launch_template" "webserver" {
  name_prefix   = "webserver"
  image_id      = "ami-0b72821e2f351e396"
  instance_type = "t2.micro"
  tags = {
    Name = "webservers"
  }
  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "ssh-rsa 2048 SHA256:UbCOIKDTVxSWGqjEK5uFwuzrPapd994fluf0fDiBdnY" >> /home/ec2-user/.ssh/authorized_keys
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from $HOSTNAME </h1>" > /var/www/html/index.html
              EOF
  )
}

resource "aws_autoscaling_group" "ASG" {
  launch_template {
    id      = aws_launch_template.webserver.id
  }
  vpc_zone_identifier = [aws_subnet.private.id]
  desired_capacity   = 2
  max_size           = 5
  min_size           = 2
}
