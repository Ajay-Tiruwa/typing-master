#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║         NEW DEVOPS PROJECT SETUP         ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"


# Ask questions
read -p "📁 Project name (no spaces): " PROJECT_NAME

if [ -z "$PROJECT_NAME" ]; then
  echo -e "${RED}❌ Project name cannot be empty.${NC}"
  exit 1
fi

if [[ "$PROJECT_NAME" == *" "* ]]; then
  echo -e "${RED}❌ Project name cannot have spaces. Use - instead.${NC}"
  exit 1
fi

if [ -d "~/$PROJECT_NAME" ]; then
  echo -e "${RED}❌ Project folder already exists.${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Project name: $PROJECT_NAME${NC}"
read -p "🔑 Path to your .pem key: " PEM_KEY
PEM_KEY="${PEM_KEY/#\~/$HOME}"

if [ ! -f "$PEM_KEY" ]; then
  echo -e "${RED}❌ PEM key not found at: $PEM_KEY${NC}"
  echo -e "${YELLOW}Check the path and try again.${NC}"
  exit 1
fi
echo -e "${GREEN}✅ PEM key found!${NC}"
read -p "🌍 AWS Region (default: ap-northeast-1): " REGION
REGION=${REGION:-ap-northeast-1}
read -p "🖥  Use existing EC2? (yes/no): " USE_EXISTING

if [ "$USE_EXISTING" == "yes" ]; then
  read -p "📋 Paste your EC2 Instance ID: " INSTANCE_ID
else
  echo ""
  echo -e "${YELLOW}⏳ Launching new EC2 instance...${NC}"

  # Get default VPC
  VPC_ID=$(aws ec2 describe-vpcs \
    --region $REGION \
    --filters Name=isDefault,Values=true \
    --query 'Vpcs[0].VpcId' \
    --output text)

  # Get default subnet
  SUBNET_ID=$(aws ec2 describe-subnets \
    --region $REGION \
    --filters Name=vpc-id,Values=$VPC_ID \
    --query 'Subnets[0].SubnetId' \
    --output text)

  # Create security group
  SG_ID=$(aws ec2 create-security-group \
    --group-name "$PROJECT_NAME-sg" \
    --description "Security group for $PROJECT_NAME" \
    --vpc-id $VPC_ID \
    --region $REGION \
    --query 'GroupId' \
    --output text)

  # Add rules
  aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 --region $REGION > /dev/null
  aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $REGION > /dev/null
  aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0 --region $REGION > /dev/null

  # Get Ubuntu AMI
  AMI_ID=$(aws ec2 describe-images \
    --region $REGION \
    --owners 099720109477 \
    --filters Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-* \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)

  # Create key pair
  aws ec2 create-key-pair \
    --key-name "$PROJECT_NAME-key" \
    --region $REGION \
    --query 'KeyMaterial' \
    --output text > ~/$PROJECT_NAME-key.pem

  chmod 400 ~/$PROJECT_NAME-key.pem
  PEM_KEY=~/$PROJECT_NAME-key.pem
  echo -e "${GREEN}✅ Key saved to: $PEM_KEY${NC}"

  # Launch EC2
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t2.micro \
    --key-name "$PROJECT_NAME-key" \
    --security-group-ids $SG_ID \
    --subnet-id $SUBNET_ID \
    --region $REGION \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$PROJECT_NAME}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

  echo -e "${GREEN}✅ EC2 launched: $INSTANCE_ID${NC}"
  echo "⏳ Waiting for instance to be running..."
  aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION
fi

# Allocate Elastic IP
echo ""
echo -e "${YELLOW}🌐 Allocating Elastic IP...${NC}"
ALLOCATION_ID=$(aws ec2 allocate-address \
  --domain vpc \
  --region $REGION \
  --query 'AllocationId' \
  --output text)

aws ec2 associate-address \
  --instance-id $INSTANCE_ID \
  --allocation-id $ALLOCATION_ID \
  --region $REGION > /dev/null

PUBLIC_IP=$(aws ec2 describe-addresses \
  --allocation-ids $ALLOCATION_ID \
  --region $REGION \
  --query 'Addresses[0].PublicIp' \
  --output text)

echo -e "${GREEN}✅ Elastic IP: $PUBLIC_IP${NC}"

# Wait for SSH to be ready
echo ""
echo "⏳ Waiting for server to be ready for SSH..."
sleep 30

# Install Nginx
echo -e "${YELLOW}🌐 Installing Nginx on server...${NC}"
ssh -i $PEM_KEY -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP "
  sudo apt update -y > /dev/null 2>&1
  sudo apt install -y nginx > /dev/null 2>&1
  sudo systemctl start nginx
  sudo systemctl enable nginx
  sudo chown -R ubuntu:ubuntu /var/www/html
"
echo -e "${GREEN}✅ Nginx installed and running!${NC}"

# Create project folder
echo ""
echo -e "${YELLOW}📁 Setting up project folder...${NC}"
mkdir -p ~/$PROJECT_NAME/.github/workflows

# Create index.html
# Choose index.html
echo ""
echo -e "${YELLOW}📄 Do you want to use your own HTML file?${NC}"
read -p "Paste full path to your HTML file (or press Enter to skip): " HTML_PATH

if [ -z "$HTML_PATH" ]; then
  echo -e "${YELLOW}Using blank starter page...${NC}"
  cat > ~/$PROJECT_NAME/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head><title>New Project</title></head>
<body>
<h1>My New DevOps Project</h1>
<p>Deployed automatically with GitHub Actions</p>
</body>
</html>
HTMLEOF
else
  HTML_PATH="${HTML_PATH/#\~/$HOME}"
  if [ -f "$HTML_PATH" ]; then
    cp "$HTML_PATH" ~/$PROJECT_NAME/index.html
    echo -e "${GREEN}✅ Your file copied as index.html${NC}"
  else
    echo -e "${RED}❌ File not found at: $HTML_PATH${NC}"
    echo -e "${RED}❌ Stopping. Fix the path and try again.${NC}"
    exit 1
  fi
fi
```

# Copy puri.sh and update it
cp ~/devops-portfolio/puri.sh ~/$PROJECT_NAME/puri.sh
sed -i '' "s|INSTANCE_ID=.*|INSTANCE_ID=\"$INSTANCE_ID\"|" ~/$PROJECT_NAME/puri.sh
sed -i '' "s|REGION=.*|REGION=\"$REGION\"|" ~/$PROJECT_NAME/puri.sh
sed -i '' "s|PEM_KEY=.*|PEM_KEY=$PEM_KEY|" ~/$PROJECT_NAME/puri.sh

echo -e "${GREEN}✅ puri.sh copied and updated!${NC}"

# Create GitHub repo and push
echo ""
echo -e "${YELLOW}🐙 Creating GitHub repo and pushing code...${NC}"
cd ~/$PROJECT_NAME
git init
git add .
git commit -m "initial commit"
git branch -M main
gh repo create $PROJECT_NAME --public --source=. --remote=origin --push

# Add GitHub secrets
echo ""
echo -e "${YELLOW}🔐 Adding GitHub secrets...${NC}"
cat $PEM_KEY | gh secret set EC2_SSH_KEY --repo Ajay-Tiruwa/$PROJECT_NAME
gh secret set EC2_HOST --body "$PUBLIC_IP" --repo Ajay-Tiruwa/$PROJECT_NAME
gh secret set EC2_USER --body "ubuntu" --repo Ajay-Tiruwa/$PROJECT_NAME
echo -e "${GREEN}✅ GitHub secrets added!${NC}"

# Done
echo ""
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════╗"
echo "║         ✅ PROJECT READY!                 ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "📁 Project folder: ~/$PROJECT_NAME"
echo -e "🌐 Site URL:       http://$PUBLIC_IP"
echo -e "🐙 GitHub repo:    github.com/Ajay-Tiruwa/$PROJECT_NAME"
echo -e "🖥  EC2 Instance:   $INSTANCE_ID"
echo -e "🔑 PEM Key:        $PEM_KEY"
echo ""
echo -e "${YELLOW}To manage this project run:${NC}"
echo "  ~/$PROJECT_NAME/puri.sh"
echo ""
echo -e "${YELLOW}To deploy changes:${NC}"
echo "  cd ~/$PROJECT_NAME"
echo "  git add . && git commit -m 'update' && git push"
