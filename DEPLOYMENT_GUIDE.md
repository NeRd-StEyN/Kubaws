# 🚀 Automated Deployment Guide

## How It Works

```
You edit App.jsx → git push
    ↓
GitHub Actions automatically:
  1. Builds Docker images (Frontend + Backend)
  2. Pushes to GitHub Container Registry
  3. Images are publicly available
    ↓
Your EC2 server:
  - Pulls latest images on boot
  - OR manually update with single command
```

## 📋 Setup Steps (One-Time)

### Step 1: Push Your Code to GitHub

```bash
git add .
git commit -m "Setup automated deployment"
git push origin main
```

GitHub Actions will automatically build and push your Docker images!

### Step 2: Make Images Public

1. Go to: https://github.com/YOUR_USERNAME?tab=packages
2. Click on `kubaws/frontend` package
3. Click "Package settings" → "Change visibility" → "Public"
4. Repeat for `kubaws/backend`

### Step 3: Deploy Updated EC2

```bash
cd terraform
terraform apply -replace="aws_instance.app_server" -auto-approve
```

Wait 3 minutes → Your custom app is live at the IP address shown!

---

## 🔄 Daily Workflow (After Setup)

### To Update Frontend (App.jsx):

```bash
# 1. Edit your code
vi frontend/src/App.jsx

# 2. Commit and push
git add frontend/
git commit -m "Updated homepage header"
git push

# 3. Wait 2 minutes for GitHub Actions to build

# 4. Update EC2 (only if it's already running)
ssh ec2-user@YOUR_IP << 'EOF'
  docker pull ghcr.io/nerd-steyn/kubaws/frontend:latest
  docker stop frontend && docker rm frontend
  docker run -d --name frontend --restart always -p 80:80 ghcr.io/nerd-steyn/kubaws/frontend:latest
EOF
```

**Total time:** 3 minutes (vs 15 minutes manual!)

---

## 🎯 Even Faster: Auto-Deploy on EC2

Want the EC2 to automatically pull new images? Add this to your `main.tf`:

```bash
# Add a cron job to check for updates every hour
echo "0 * * * * docker pull ghcr.io/nerd-steyn/kubaws/frontend:latest && docker restart frontend" | crontab -
```

Then updates happen **fully automatically**!

---

## 📊 What Gets Automated

| Task | Before | After |
|------|--------|-------|
| Build React app | `npm run build` (manual) | Automatic on push |
| Build Docker image | `docker build .` (manual) | Automatic on push |
| Push to registry | `docker push` (manual) | Automatic on push |
| Deploy to EC2 | Terraform replace (5 min) | Optional: 30 sec SSH |

---

## 🔍 Monitoring Your Builds

View build status:
- https://github.com/NeRd-StEyN/Kubaws/actions

Each push shows:
- ✅ Build succeeded
- 📦 Image pushed
- 🐳 Image tag (e.g., `main-abc123`)

---

## 🛠 Troubleshooting

**GitHub Actions failing?**
- Check: https://github.com/YOUR_USERNAME/Kubaws/actions
- Look for red ❌ marks
- Click to see error logs

**EC2 not pulling images?**
```bash
# SSH into EC2 and check logs
ssh ec2-user@YOUR_IP
sudo cat /var/log/user-data.log
```

**Images not public?**
- Make sure both packages are set to "Public" visibility
- GitHub Container Registry URL: `ghcr.io/YOUR_USERNAME/kubaws`

---

## 🎓 Next Steps

1. Test the current setup (push a change to App.jsx)
2. Add ArgoCD for Kubernetes-style deployments
3. Set up production environment with EKS
