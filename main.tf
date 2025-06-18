terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.70.0"
    }
  }
}

provider "aws" {
  region     = "ap-northeast-2"
  access_key = ""
  secret_key = ""
}

# 1. VPC 생성
resource "aws_vpc" "gaguyo_vpc_tf" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "gaguyo_vpc_tf"
    Environment = "dev"
  }
}

# 2. 퍼블릭 서브넷 생성
resource "aws_subnet" "gaguyo_public_subnet_tf" {
  vpc_id                  = aws_vpc.gaguyo_vpc_tf.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "gaguyo_public_subnet_tf"
  }
}

# 3. 프라이빗 서브넷 생성
resource "aws_subnet" "gaguyo_private_subnet_tf" {
  vpc_id                  = aws_vpc.gaguyo_vpc_tf.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = false

  tags = {
    Name = "gaguyo_private_subnet_tf"
  }
}

# 4. 인터넷 게이트웨이 생성
resource "aws_internet_gateway" "gaguyo_igw_tf" {
  vpc_id = aws_vpc.gaguyo_vpc_tf.id

  tags = {
    Name = "gaguyo_igw_tf"
  }
}

# 5. 퍼블릭 라우팅 테이블 생성
resource "aws_route_table" "gaguyo_public_rt_tf" {
  vpc_id = aws_vpc.gaguyo_vpc_tf.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gaguyo_igw_tf.id
  }

  tags = {
    Name = "gaguyo_public_rt_tf"
  }
}

# 6. 퍼블릭 라우팅 테이블을 퍼블릭 서브넷에 연결
resource "aws_route_table_association" "gaguyo_public_rt_assoc_tf" {
  subnet_id      = aws_subnet.gaguyo_public_subnet_tf.id
  route_table_id = aws_route_table.gaguyo_public_rt_tf.id
}


###############################################

# 7. Elastic IP (NAT용)
# resource "aws_eip" "gaguyo_nat_eip_tf" {
#   domain = "vpc"
#   depends_on = [aws_internet_gateway.gaguyo_igw_tf]
# }

# 8. NAT Gateway (퍼블릭 서브넷에 위치)
# resource "aws_nat_gateway" "gaguyo_nat_gw_tf" {
#   allocation_id = aws_eip.gaguyo_nat_eip_tf.id
#   subnet_id     = aws_subnet.gaguyo_public_subnet_tf.id
#   tags = {
#     Name = "gaguyo_nat_gw_tf"
#   }

#   depends_on = [aws_internet_gateway.gaguyo_igw_tf]
# }

# 9. 프라이빗 라우팅 테이블
resource "aws_route_table" "gaguyo_private_rt_tf" {
  vpc_id = aws_vpc.gaguyo_vpc_tf.id
  # route {
  #   cidr_block     = "0.0.0.0/0"
  #   nat_gateway_id = aws_nat_gateway.gaguyo_nat_gw_tf.id
  # }
  tags = {
    Name = "gaguyo_private_rt_tf"
  }
}

# 10. 프라이빗 서브넷에 라우팅 테이블 연결
resource "aws_route_table_association" "gaguyo_private_rt_assoc_tf" {
  subnet_id      = aws_subnet.gaguyo_private_subnet_tf.id
  route_table_id = aws_route_table.gaguyo_private_rt_tf.id
}


# 11. 보안 그룹 (SSH, HTTP 허용)
resource "aws_security_group" "gaguyo_wordpress_sg_tf" {
  name        = "gaguyo_wordpress_sg_tf"
  description = "Allow HTTP, SSH inbound traffic"
  vpc_id      = aws_vpc.gaguyo_vpc_tf.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
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
    Name = "gaguyo_wordpress_sg_tf"
  }
}

# 12. 
resource "aws_iam_role" "docker_logs_role_tf" {
  name = "docker-logs-role_tf"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# 13. 
resource "aws_iam_role_policy" "docker_logs_policy_tf" {
  name = "allow-cloudwatch-logs_tf"
  role = aws_iam_role.docker_logs_role_tf.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      Resource = "*"
    }]
  })
}

# 14. 
resource "aws_iam_instance_profile" "docker_logs_instance_profile_tf" {
  name = "docker-logs-instance-profile_tf"
  role = aws_iam_role.docker_logs_role_tf.name
}


# 15. Wordpress EC2 인스턴스 (Public Subnet)
resource "aws_instance" "gaguyo_wordpress_ec2_tf" {
  ami           = "ami-07245923df267c46c"  # 사용자 지정 AMI ID
  instance_type = "t3.small"
  subnet_id     = aws_subnet.gaguyo_public_subnet_tf.id
  vpc_security_group_ids = [aws_security_group.gaguyo_wordpress_sg_tf.id]
  key_name      = "gaguyo"  # AWS에 생성해둔 키페어 이름

  iam_instance_profile = aws_iam_instance_profile.docker_logs_instance_profile_tf.name

  root_block_device {
    volume_size = 32         # 디스크 크기 (GiB)
    volume_type = "gp2"      # gp2, gp3, io1, sc1 등 가능
    delete_on_termination = true  # 인스턴스 삭제 시 볼륨도 삭제
  }

  tags = {
    Name = "gaguyo_wordpress_ec2_tf"
  }
}



# 16. 보안 그룹 (SSH, MariaDB 허용)
resource "aws_security_group" "gaguyo_db_sg_tf" {
  name        = "gaguyo_db_sg_tf"
  description = "Allow MariaDB, SSH inbound traffic"
  vpc_id      = aws_vpc.gaguyo_vpc_tf.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/24"]
  }

  ingress {
    description = "MariaDB"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "gaguyo_db_sg_tf"
  }
}


# 17. DB EC2 인스턴스 (Private Subnet)
resource "aws_instance" "gaguyo_db_ec2_tf" {
  ami           = "ami-081452b213a669566"  # 사용자 지정 AMI ID
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.gaguyo_private_subnet_tf.id
  vpc_security_group_ids = [aws_security_group.gaguyo_db_sg_tf.id]
  key_name      = "gaguyo"  # AWS에 생성해둔 키페어 이름
  private_ip    = "10.0.1.204" # DB private IP 고정
  
  root_block_device {
    volume_size = 32         # 디스크 크기 (GiB)
    volume_type = "gp2"      # gp2, gp3, io1, sc1 등 가능
    delete_on_termination = true  # 인스턴스 삭제 시 볼륨도 삭제
  }

  tags = {
    Name = "gaguyo_db_ec2_tf"
  }
}

# 17. Cloudwatch log group 생성
resource "aws_cloudwatch_log_group" "gaguyo_logs_tf" {
  name              = "gaguyo_logs_tf"  # 로그 그룹 이름
  retention_in_days = 3                 # 로그 보관 기간 (예: 3일)
  tags = {
    Name = "gaguyo_logs_tf"
    Environment = "dev"
  }
}

