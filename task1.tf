provider "aws" {
  region = "ap-south-1"
  profile = "mymilind"
}


resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key1"
  public_key = "${tls_private_key.example.public_key_openssh}"
}
resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow tls inbound traffic"
  vpc_id      = "vpc-f6869b9e"

  ingress {
    description = "tls from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "TLS from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "Tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_tls"
  }
}
resource "aws_instance" "web" {
  depends_on = [aws_key_pair.deployer,aws_security_group.allow_tls,]
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = "deployer-key1"
  security_groups = ["allow_tls"]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.example.private_key_pem
    host     = aws_instance.web.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }
  tags = {
    Name = "WEBSERVER"
    }
}

resource "aws_ebs_volume" "ebs" {
  availability_zone = aws_instance.web.availability_zone
  size              = 1
  tags = {
    Name = "storage"
  }
}


resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = "${aws_ebs_volume.ebs.id}"
  instance_id = "${aws_instance.web.id}"
  force_detach = true
}

resource "null_resource" "nullremote1"  {

depends_on = [
    aws_volume_attachment.ebs_att,aws_instance.web,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.example.private_key_pem	
    host     = aws_instance.web.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/MilindRastogi/Terraform_webserver_automation.git /var/www/html/"
    ]
  }
}

       
resource "aws_s3_bucket" "b" {
  bucket = "milind2000"
  acl    = "public-read"

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}
resource "null_resource" "nulllocal1"  {

	provisioner "local-exec" {
	    command = "curl -O https://raw.githubusercontent.com/MilindRastogi/Terraform_webserver_automation/master/Terraform-main-image.jpg"
  	}
}

resource "aws_s3_bucket_object" "object" {
  depends_on = [aws_s3_bucket.b,]
  bucket = "milind2000"
  key    = "teraimage.jpg"
  source = "Terraform-main-image.jpg"
  acl = "public-read"

  # The filemd5() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the md5() function and the file() function:
  # etag = "${md5(file("path/to/file"))}"
  
}
locals {
  s3_origin_id = "S3-milind2000"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
depends_on = [aws_instance.web,aws_s3_bucket_object.object,]
  origin {
    domain_name = "milind2000.s3.amazonaws.com"
    origin_id   = "${local.s3_origin_id}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "teraimage.jpg"


  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }


  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "null_resource" "cloudfront_url"{
  depends_on = [aws_cloudfront_distribution.s3_distribution,]
  connection {
    type     = "ssh"
    user     = "ec2-user"
   private_key = tls_private_key.example.private_key_pem	
    host     = aws_instance.web.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo sed -i '$ a <img src= 'https://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.object.key}' height = '400' width='400'>' /var/www/html/index.html",
      "sudo systemctl restart httpd",
    ]
  }
}


resource "null_resource" "local1"{
depends_on = [
    null_resource.cloudfront_url,
]
provisioner "local-exec" {
    command = "start chrome ${aws_instance.web.public_ip} "
  }
}