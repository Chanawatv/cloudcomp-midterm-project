terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.39"
    }
  }

  required_version = ">= 1.2.0"
}

variable "region" {
  description = "The AWS region to deploy resources"
}

variable "availability_zone" {
  description = "The availability zone for resources"
}

variable "ami" {
  description = "The AMI ID for instances"
}

variable "bucket_name" {
  description = "The name of the S3 bucket"
}

variable "database_name" {
  description = "The name of the database"
}

variable "database_user" {
  description = "The database username"
}

variable "database_pass" {
  description = "The database password"
}

variable "admin_user" {
  description = "The admin username"
}

variable "admin_pass" {
  description = "The admin password"
}

# Define the AWS provider
provider "aws" {
  region = var.region
}

# Define the VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  # enable_dns_hostnames = true

  tags = {
    Name = "wordpress-vpc"
  }
}

# Define the Internet Gateway for public subnets
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "wordpress-igw"
  }
}

# Define public subnet for WordPress with Elastic IP
resource "aws_subnet" "wordpress_public_subnet" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.availability_zone
  # map_public_ip_on_launch = true

  tags = {
    Name = "wordpress-public-subnet"
  }
}

# Define public subnet for NAT Gateway
resource "aws_subnet" "nat_public_subnet" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = var.availability_zone
  # map_public_ip_on_launch = true

  tags = {
    Name = "nat-public-subnet"
  }
}

# Define private subnet for MariaDB server
resource "aws_subnet" "mariadb_private_subnet" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = var.availability_zone

  tags = {
    Name = "mariadb-private-subnet"
  }
}

# Define private subnet for interface between WordPress and MariaDB
resource "aws_subnet" "interface_private_subnet" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = var.availability_zone

  tags = {
    Name = "interface-private-subnet"
  }
}

# Define Elastic IP for WordPress instance
resource "aws_eip" "wordpress_eip" {
  tags = {
    Name = "wordpress-eip"
  }
}

# Define Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  tags = {
    Name = "nat-eip"
  }
}

# Define a NAT Gateway for mariadb
resource "aws_nat_gateway" "mariadb_nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.nat_public_subnet.id

  tags = {
    Name = "mariadb-nat-gateway"
  }
}

# Create a route table for public subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Create a route table for private subnets
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.mariadb_nat_gateway.id
  }

  tags = {
    Name = "private-route-table"
  }
}

# Create a route table for interface subnets
resource "aws_route_table" "interface_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "interface-route-table"
  }
}

# Associate public route table with public subnets
resource "aws_route_table_association" "wordpress_public_route_association" {
  subnet_id      = aws_subnet.wordpress_public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "nat_public_route_association" {
  subnet_id      = aws_subnet.nat_public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Associate private route table with private subnets
resource "aws_route_table_association" "mariadb_private_route_association" {
  subnet_id      = aws_subnet.mariadb_private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "interface_private_route_association" {
  subnet_id      = aws_subnet.interface_private_subnet.id
  route_table_id = aws_route_table.interface_route_table.id
}

# Define a security group for WordPress
resource "aws_security_group" "wordpress_security_group" {
  name       = "wordpress_security_group"
  vpc_id     = aws_vpc.wordpress_vpc.id

  ingress { // http
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress { // https
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress { // ssh
    from_port   = 22
    to_port     = 22
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
    Name = "wordpress_security_group"
  }
}

# Define a security group for WordPress interface with MariaDB
resource "aws_security_group" "wordpress_mariadb_security_group" {
  name       = "wordpress_maraidb_security_group"
  vpc_id     = aws_vpc.wordpress_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress_mariadb_security_group"
  }
}

# Define a security group for MariaDB interface with WordPress
resource "aws_security_group" "mariadb_wordpress_security_group" {
  name       = "mariadb_wordpress_security_group"
  vpc_id     = aws_vpc.wordpress_vpc.id

  ingress { // mysql
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.wordpress_mariadb_security_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mariadb_wordpress_security_group"
  }
}

# Define a security group for MariaDB
resource "aws_security_group" "mariadb_security_group" {
  name       = "mariadb-security-group"
  vpc_id     = aws_vpc.wordpress_vpc.id

  ingress { // ssh
    from_port   = 22
    to_port     = 22
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
    Name = "mariadb-security-group"
  }
}

# Define network interfaces for WordPress
resource "aws_network_interface" "wordpress_network_interface" {
  subnet_id   = aws_subnet.wordpress_public_subnet.id
  security_groups = [aws_security_group.wordpress_security_group.id]
}

resource "aws_eip_association" "wordpress_eip_association" {
  allocation_id = aws_eip.wordpress_eip.id
  network_interface_id = aws_network_interface.wordpress_network_interface.id
}

resource "aws_network_interface" "wordpress_mariadb_network_interface" {
  subnet_id   = aws_subnet.interface_private_subnet.id
  security_groups = [aws_security_group.wordpress_mariadb_security_group.id]
}

# Define network interfaces for MariaDB
resource "aws_network_interface" "mariadb_network_interface" {
  subnet_id   = aws_subnet.mariadb_private_subnet.id
  security_groups = [aws_security_group.mariadb_security_group.id]
}

resource "aws_network_interface" "mariadb_wordpress_network_interface" {
  subnet_id   = aws_subnet.interface_private_subnet.id
  security_groups = [aws_security_group.mariadb_wordpress_security_group.id]
}

# Define an IAM user for accessing S3 bucket
resource "aws_iam_user" "wordpress_s3_user" {
  name = "wordpress_s3_user"
  tags = {
    Name = "wordpress-s3-user"
  }
}

resource "aws_iam_user_policy_attachment" "wordpress_s3_access_policy_attachment" {
  user       = aws_iam_user.wordpress_s3_user.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_access_key" "wordpress_s3_access_key" {
  user = aws_iam_user.wordpress_s3_user.name
}

# Define an S3 bucket for WordPress
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = var.bucket_name
  force_destroy = true
  tags = {
    Name = "wordpress-bucket"
  }
}

resource "aws_s3_bucket_ownership_controls" "wordpress_bucket_ownership_controls" {
  bucket = aws_s3_bucket.wordpress_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "wordpress_bucket_public_access_block" {
  bucket = aws_s3_bucket.wordpress_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "wordpress_bucket_acl" {
  depends_on = [ 
    aws_s3_bucket_ownership_controls.wordpress_bucket_ownership_controls,
    aws_s3_bucket_public_access_block.wordpress_bucket_public_access_block,
  ]
  bucket = aws_s3_bucket.wordpress_bucket.id
  acl    = "public-read"
}

# Define a MariaDB instance
resource "aws_instance" "mariadb_instance" {
  depends_on = [ 
    aws_nat_gateway.mariadb_nat_gateway,
    aws_route_table_association.mariadb_private_route_association,
  ]

  ami           = var.ami
  instance_type = "t2.micro"
  availability_zone = var.availability_zone

  network_interface {
    network_interface_id = aws_network_interface.mariadb_network_interface.id
    device_index         = 0
  }

  network_interface {
    network_interface_id = aws_network_interface.mariadb_wordpress_network_interface.id
    device_index         = 1
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo systemctl restart ssh
              sudo apt update -y
              sudo apt install mariadb-server-10.6 -y
              sudo systemctl start mariadb
              sudo systemctl enable mariadb
              sudo mysql -e "CREATE DATABASE ${var.database_name};"
              sudo mysql -e "CREATE USER '${var.database_user}'@'%' IDENTIFIED BY '${var.database_pass}';"
              sudo mysql -e "GRANT ALL PRIVILEGES ON ${var.database_name}.* TO '${var.database_user}'@'%';"
              sudo mysql -e "FLUSH PRIVILEGES;"
              sudo sed -i "s/127.0.0.1/0.0.0.0/" /etc/mysql/mariadb.conf.d/50-server.cnf
              sudo systemctl restart mariadb
              EOF

  tags = {
    Name = "mariadb-instance"
  }
}

# Define a WordPress instance
resource "aws_instance" "wordpress_instance" {
  depends_on = [ 
    aws_instance.mariadb_instance
  ]

  ami           = var.ami
  instance_type = "t2.micro"
  availability_zone = var.availability_zone

  network_interface {
    network_interface_id = aws_network_interface.wordpress_network_interface.id
    device_index         = 0
  }

  network_interface {
    network_interface_id = aws_network_interface.wordpress_mariadb_network_interface.id
    device_index         = 1
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo systemctl restart ssh
              sudo apt update -y
              sudo apt install apache2 php8.1 php8.1-curl php8.1-mysql php8.1-gd php8.1-xml php8.1-mbstring php8.1-xmlrpc php8.1-zip php8.1-soap php8.1-intl wget -y
              sudo systemctl start apache2
              sudo systemctl enable apache2
              sudo wget https://wordpress.org/latest.tar.gz
              sudo tar -xvf latest.tar.gz
              sudo cp -r wordpress/* /var/www/html/
              sudo chown -R www-data:www-data /var/www/html/
              sudo chmod -R 755 /var/www/html/
              sudo cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
              sudo sed -i "s/database_name_here/${var.database_name}/" /var/www/html/wp-config.php
              sudo sed -i "s/username_here/${var.database_user}/" /var/www/html/wp-config.php
              sudo sed -i "s/password_here/${var.database_pass}/" /var/www/html/wp-config.php
              sudo sed -i "s/localhost/${aws_network_interface.mariadb_wordpress_network_interface.private_ip}/" /var/www/html/wp-config.php
              sudo sed -i "/define( 'WP_DEBUG', false );/a define( 'AS3CF_SETTINGS', serialize( array(\n\t'provider' => 'aws',\n\t'access-key-id' => '${aws_iam_access_key.wordpress_s3_access_key.id}',\n\t'secret-access-key' => '${aws_iam_access_key.wordpress_s3_access_key.secret}',\n\t'bucket' => '${aws_s3_bucket.wordpress_bucket.id}',\n\t'region' => '${var.region}',\n\t'copy-to-s3' => true,\n\t'serve-from-s3' => true,\n) ) );" /var/www/html/wp-config.php
              sudo systemctl restart apache2
              sudo wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
              sudo chmod +x wp-cli.phar
              sudo mv wp-cli.phar /usr/local/bin/wp
              sudo wp core install --path=/var/www/html --allow-root --url=${aws_eip.wordpress_eip.public_ip} --title="Cloud Midterm" --admin_user=${var.admin_user} --admin_password=${var.admin_pass} --admin_email="example@example.com" --skip-email
              sudo wp plugin install amazon-s3-and-cloudfront --path=/var/www/html --allow-root --activate
              sudo systemctl restart apache2
              EOF

  tags = {
    Name = "wordpress-instance"
  }
}

resource "aws_ec2_instance_connect_endpoint" "mariadb_vpc_endpoint" {
  subnet_id = aws_subnet.mariadb_private_subnet.id
}