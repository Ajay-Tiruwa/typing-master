#!/bin/bash

INSTANCE_ID="i-01afe6688eee0cd53"
REGION="ap-northeast-1"
ELASTIC_IP=$(aws ec2 describe-addresses \
  --region $REGION \
  --query 'Addresses[0].PublicIp' \
  --output text)
PEM_KEY=/Users/ajaytiruwa/typing-master/pdevops.pem

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

clear

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║       AJAY DEVOPS CONTROL PANEL          ║"
echo "║           AWS EC2 Manager                ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# Show EC2 status at the top every time
STATUS=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --region $REGION \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text)

if [ "$STATUS" == "running" ]; then
  echo -e "EC2 Status: ${GREEN}● RUNNING${NC} — http://$ELASTIC_IP"
elif [ "$STATUS" == "stopped" ]; then
  echo -e "EC2 Status: ${RED}● STOPPED${NC}"
else
  echo -e "EC2 Status: ${YELLOW}● $STATUS${NC}"
fi

echo ""
echo -e "${YELLOW}What do you want to do?${NC}"
echo ""
echo "  1) Start EC2"
echo "  2) Stop EC2"
echo "  3) SSH into EC2"
echo "  4) Open site in browser"
echo "  5) Check GitHub Actions"
echo "  6) Push code to GitHub"
echo "  7) Show server stats (CPU, memory, disk)"
echo "  8) View Nginx live logs"
echo "  9) Restart Nginx"
echo " 10) Backup website to Mac"
echo " 11) Check AWS free tier + open billing"
echo " 12) ⚠️  STOP EVERYTHING (avoid charges)"
echo " 13) Exit"
echo ""
read -p "Choose an option [1-13]: " choice
case $choice in

  1)
    echo -e "${YELLOW}🚀 Starting EC2...${NC}"
    aws ec2 start-instances --instance-ids $INSTANCE_ID --region $REGION > /dev/null
    echo "⏳ Waiting for instance to be running..."
    aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION
    echo -e "${GREEN}✅ EC2 is running!${NC}"

    echo ""
    echo -e "${YELLOW}🌐 Allocating new Elastic IP...${NC}"
    ALLOCATION_ID=$(aws ec2 allocate-address \
      --domain vpc \
      --region $REGION \
      --query 'AllocationId' \
      --output text)

    aws ec2 associate-address \
      --instance-id $INSTANCE_ID \
      --allocation-id $ALLOCATION_ID \
      --region $REGION > /dev/null

    NEW_IP=$(aws ec2 describe-addresses \
      --allocation-ids $ALLOCATION_ID \
      --region $REGION \
      --query 'Addresses[0].PublicIp' \
      --output text)

    echo -e "${GREEN}✅ Your new IP is: $NEW_IP${NC}"
    echo -e "🌐 Site is live at: http://$NEW_IP"

    echo ""
    echo -e "${YELLOW}📝 Updating GitHub secret EC2_HOST...${NC}"
    gh secret set EC2_HOST --body "$NEW_IP" --repo Ajay-Tiruwa/devops-portfolio
    echo -e "${GREEN}✅ GitHub secret updated automatically!${NC}"

    ELASTIC_IP=$NEW_IP
    ;;
  2)
    echo -e "${YELLOW}⏳ Stopping EC2...${NC}"
    aws ec2 stop-instances --instance-ids $INSTANCE_ID --region $REGION > /dev/null
    echo "⏳ Waiting for instance to stop..."
    aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID --region $REGION
    echo -e "${GREEN}✅ EC2 stopped!${NC}"

    echo ""
    echo -e "${YELLOW}🔍 Releasing Elastic IP to avoid charges...${NC}"
    ALLOCATION_ID=$(aws ec2 describe-addresses \
      --region $REGION \
      --query 'Addresses[0].AllocationId' \
      --output text)

    if [ "$ALLOCATION_ID" != "None" ] && [ ! -z "$ALLOCATION_ID" ]; then
      aws ec2 release-address --allocation-id $ALLOCATION_ID --region $REGION
      echo -e "${GREEN}✅ Elastic IP released — no charges will apply!${NC}"
    else
      echo -e "${YELLOW}⚠️  No Elastic IP found to release.${NC}"
    fi

    echo -e "${CYAN}💰 You will not be charged while EC2 is stopped.${NC}"
    ;;
  3)
    if [ "$STATUS" != "running" ]; then
      echo -e "${RED}❌ EC2 is not running. Start it first (option 1).${NC}"
    else
      echo -e "${GREEN}🔐 Connecting to EC2...${NC}"
      ssh -i $PEM_KEY -o StrictHostKeyChecking=no ubuntu@$ELASTIC_IP
    fi
    ;;

  4)
    if [ "$STATUS" != "running" ]; then
      echo -e "${RED}❌ EC2 is not running. Start it first (option 1).${NC}"
    else
      echo -e "${GREEN}🌐 Opening site in browser...${NC}"
      open http://$ELASTIC_IP
    fi
    ;;

  5)
    echo -e "${CYAN}📋 Recent GitHub Actions runs:${NC}"
    echo ""
    gh run list --limit 8
    ;;

  6)
    cd ~/devops-portfolio
    echo ""
    read -p "📝 Commit message: " msg
    git add .
    git commit -m "$msg"
    git push
    echo ""
    echo -e "${YELLOW}⏳ Watching deployment live...${NC}"
    gh run watch
    echo -e "${GREEN}✅ Deployment done! Site updated at http://$ELASTIC_IP${NC}"
    ;;

  7)
    if [ "$STATUS" != "running" ]; then
      echo -e "${RED}❌ EC2 is not running. Start it first (option 1).${NC}"
    else
      echo -e "${CYAN}📊 Server Stats:${NC}"
      echo ""
      ssh -i $PEM_KEY -o StrictHostKeyChecking=no ubuntu@$ELASTIC_IP "
        echo '--- CPU & Memory ---'
        top -bn1 | grep 'Cpu\|Mem'
        echo ''
        echo '--- Disk Usage ---'
        df -h /
        echo ''
        echo '--- Memory Details ---'
        free -h
        echo ''
        echo '--- Server Uptime ---'
        uptime
      "
    fi
    ;;

  8)
    if [ "$STATUS" != "running" ]; then
      echo -e "${RED}❌ EC2 is not running. Start it first (option 1).${NC}"
    else
      echo -e "${CYAN}📜 Nginx live logs (Ctrl+C to stop):${NC}"
      echo ""
      ssh -i $PEM_KEY -o StrictHostKeyChecking=no ubuntu@$ELASTIC_IP "sudo tail -f /var/log/nginx/access.log"
    fi
    ;;

  9)
    if [ "$STATUS" != "running" ]; then
      echo -e "${RED}❌ EC2 is not running. Start it first (option 1).${NC}"
    else
      echo -e "${YELLOW}🔄 Restarting Nginx...${NC}"
      ssh -i $PEM_KEY -o StrictHostKeyChecking=no ubuntu@$ELASTIC_IP "sudo systemctl restart nginx"
      echo -e "${GREEN}✅ Nginx restarted!${NC}"
    fi
    ;;

  10)
    if [ "$STATUS" != "running" ]; then
      echo -e "${RED}❌ EC2 is not running. Start it first (option 1).${NC}"
    else
      echo -e "${YELLOW}💾 Backing up website files to Mac...${NC}"
      mkdir -p ~/devops-portfolio/backup
      scp -i $PEM_KEY -o StrictHostKeyChecking=no ubuntu@$ELASTIC_IP:/var/www/html/* ~/devops-portfolio/backup/
      echo -e "${GREEN}✅ Backup saved to ~/devops-portfolio/backup/${NC}"
    fi
    ;;

  11)
    echo -e "${CYAN}📊 Checking AWS Free Tier Usage...${NC}"
    echo ""

    echo -e "${YELLOW}💾 EBS Storage (Free tier: 30 GB):${NC}"
    aws ec2 describe-volumes \
      --region $REGION \
      --query 'Volumes[*].[VolumeId,Size]' \
      --output table

    echo ""
    echo -e "${YELLOW}🌐 Elastic IPs (charged if EC2 stopped):${NC}"
    aws ec2 describe-addresses \
      --region $REGION \
      --query 'Addresses[*].[PublicIp,InstanceId]' \
      --output table

    echo ""
    echo -e "${GREEN}⚠️  Free Tier Reminders:${NC}"
    echo "  ✅ EC2 t2.micro — 750 hours/month free"
    echo "  ✅ EBS Storage  — 30 GB free"
    echo "  ✅ Data Transfer — 100 GB outbound free"
    echo "  ✅ S3           — 5 GB free"
    echo "  ⚠️  Elastic IP   — charges if EC2 is STOPPED"
    echo ""
    echo -e "${YELLOW}💳 Opening AWS Billing dashboard in browser...${NC}"
    open https://console.aws.amazon.com/billing/home#/
    ;;

  12)
    echo -e "${RED}"
    echo "╔══════════════════════════════════════════╗"
    echo "║         ⚠️  STOP EVERYTHING               ║"
    echo "║     This will stop all running AWS       ║"
    echo "║     resources to avoid charges           ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
    read -p "Are you sure? Type YES to confirm: " confirm

    if [ "$confirm" == "YES" ]; then

      echo ""
      echo -e "${YELLOW}⏳ Stopping EC2 instance...${NC}"
      aws ec2 stop-instances --instance-ids $INSTANCE_ID --region $REGION > /dev/null
      aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID --region $REGION
      echo -e "${GREEN}✅ EC2 stopped!${NC}"

      echo ""
      echo -e "${YELLOW}🔍 Checking for other running EC2 instances...${NC}"
      OTHER=$(aws ec2 describe-instances \
        --region $REGION \
        --filters Name=instance-state-name,Values=running \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text)

      if [ -z "$OTHER" ]; then
        echo -e "${GREEN}✅ No other running instances found.${NC}"
      else
        echo -e "${RED}⚠️  Found other running instances: $OTHER${NC}"
        read -p "Stop these too? (yes/no): " stopother
        if [ "$stopother" == "yes" ]; then
          aws ec2 stop-instances --instance-ids $OTHER --region $REGION > /dev/null
          echo -e "${GREEN}✅ All instances stopped!${NC}"
        fi
      fi

      echo ""
      echo -e "${YELLOW}🔍 Checking S3 buckets...${NC}"
      BUCKETS=$(aws s3 ls 2>/dev/null)
      if [ -z "$BUCKETS" ]; then
        echo -e "${GREEN}✅ No S3 buckets found.${NC}"
      else
        echo -e "${YELLOW}📦 S3 Buckets found (storage costs money):${NC}"
        echo "$BUCKETS"
      fi

      echo ""
      echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
      echo -e "${GREEN}║         ✅ ALL CLEAR                      ║${NC}"
      echo -e "${GREEN}║   EC2 stopped — no compute charges       ║${NC}"
      echo -e "${GREEN}║   Check billing to confirm               ║${NC}"
      echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
      echo ""
      echo -e "${YELLOW}💳 Opening AWS Billing to verify...${NC}"
      open https://console.aws.amazon.com/billing/home#/

    else
      echo -e "${YELLOW}Cancelled. Nothing was stopped.${NC}"
    fi
    ;;

  13)
    echo -e "${GREEN}👋 Goodbye!${NC}"
    exit 0
    ;;

esac

echo ""
read -p "Press Enter to return to menu..."
~/devops-portfolio/puri.sh
