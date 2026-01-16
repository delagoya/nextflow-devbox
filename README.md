# nf-core VS Code Server on AWS

Deploy a cloud-based VS Code Server instance optimized for Nextflow pipeline development using Amazon Linux 2023.

## Overview

This CloudFormation template creates:
- EC2 instance running VS Code Server with Amazon Linux 2023
- CloudFront distribution for secure access
- Pre-installed tools: Nextflow, nf-core, Docker, Miniconda, AWS CLI, GitHub CLI
- SSH access via AWS Systems Manager generated key pair
- Automated bootstrap via SSM documents

## Prerequisites

- AWS CLI installed and configured
- AWS account with appropriate permissions (EC2, CloudFormation, IAM, CloudFront, SSM, Secrets Manager)
- GitHub personal access token (optional, for GitHub CLI)
- Seqera Tower access token (optional, for Wave and Seqera Containers)

## Quick Start

### 1. Configure Parameters

Copy  `cfn-stack-parameters.yaml.example` to  `cfn-stack-parameters.yaml` and edit the file with your settings:

```bash
# Open the parameters file in your editor
nano cfn-stack-parameters.yaml
```

**Required parameters to update:**
- `GitUserName`: Your name for Git commits
- `GitUserEmail`: Your email for Git commits

**Optional parameters:**
- `TowerAccessToken`: Seqera Tower access token
- `GithubAccessToken`: GitHub personal access token
- `InstanceType`: EC2 instance type (default: m7g.2xlarge)
- `InstanceVolumeSize`: EBS volume size in GB (default: 100)
- `RepoUrl`: Git repository to clone on startup
- `MyIPCidrRange`: IP range for SSH access (default: 0.0.0.0/0)

**Multiple Environment Support:**

You can create different parameter files for different environments:

```bash
# Create environment-specific parameter files
cp cfn-stack-parameters.yaml dev-params.yaml
cp cfn-stack-parameters.yaml prod-params.yaml

# Edit each file with environment-specific values
# Then deploy using the appropriate file:
./deploy.sh -p dev-params.yaml    # Deploy development environment
./deploy.sh -p prod-params.yaml   # Deploy production environment
```

### 2. Deploy the Stack

Run the deployment script:

```bash
chmod +x deploy.sh
./deploy.sh
```

**Using a custom parameters file:**

```bash
# Use a different parameters file
./deploy.sh -p my-custom-params.yaml

# Or using the long form
./deploy.sh --param-file production-params.yaml
```

**Command line options:**
- `-p, --param-file FILE`: Specify CloudFormation parameters file (default: `cfn-stack-parameters.yaml`)
- `-h, --help`: Show help message

The script will:
- ✓ Automatically detect your current public IP for SSH security
- ✓ Validate required files
- ✓ Read parameters from `cfn-stack-parameters.yaml`
- ✓ Deploy the CloudFormation stack
- ✓ Monitor deployment progress in real-time
- ✓ Display stack outputs when complete
- ✓ Save outputs to `stack-outputs.txt`

Deployment typically takes 10-15 minutes.

### 3. Access Information

After deployment completes, the script displays:
- **URL**: VS Code Server web interface URL
- **Password**: Login password
- **SSHKeyPairID**: SSH key pair ID for SSH access
- **SSH commands**: Commands to download key and connect

You can also view outputs anytime:

```bash
cat stack-outputs.txt
```

Or query directly:

```bash
aws cloudformation describe-stacks \
  --stack-name nf-core-vscode-server \
  --query 'Stacks[0].Outputs'
```

### 4. Access VS Code Server

**Option A: Web Browser**
- Open the URL from the outputs
- Enter the password when prompted

**Option B: Remote SSH (Recommended)**
- See the [Remote SSH Development](#remote-ssh-development) section below

## Remote SSH Development

You can connect to the EC2 instance using VS Code or Kiro's Remote-SSH extension for a native development experience.

### Quick Setup (Recommended)

The deployment automatically generates SSH configuration that you can append to your `~/.ssh/config` file:

```bash
# Download SSH key and append SSH config in one command
eval "$(aws cloudformation describe-stacks \
  --stack-name nf-core-vscode-server \
  --query 'Stacks[0].Outputs[?OutputKey==`SSHKeyDownloadCommand`].OutputValue' \
  --output text)"

# Append SSH configuration to your config file
aws cloudformation describe-stacks \
  --stack-name nf-core-vscode-server \
  --query 'Stacks[0].Outputs[?OutputKey==`SSHConfig`].OutputValue' \
  --output text >> ~/.ssh/config
```

That's it! You can now connect using:
```bash
ssh VSCodeServer
```

### Manual Setup (Alternative)

If you prefer to set up SSH manually:

### 1. Download SSH Key

```bash
# Get the key pair ID from stack outputs
KEY_PAIR_ID=$(aws cloudformation describe-stacks \
  --stack-name nf-core-vscode-server \
  --query 'Stacks[0].Outputs[?OutputKey==`SSHKeyPairID`].OutputValue' \
  --output text)

# Download and save the private key
aws ssm get-parameter \
  --name /ec2/keypair/${KEY_PAIR_ID} \
  --with-decryption \
  --query Parameter.Value \
  --output text > ~/.ssh/nf-core-vscode-server.pem

# Set correct permissions
chmod 400 ~/.ssh/nf-core-vscode-server.pem
```

### 2. Get Instance Connection Details

```bash
# Get the instance public DNS name
INSTANCE_DNS=$(aws cloudformation describe-stack-resources \
  --stack-name nf-core-vscode-server \
  --logical-resource-id VSCodeInstance \
  --query 'StackResources[0].PhysicalResourceId' | xargs aws ec2 describe-instances \
  --instance-ids $(cat) \
  --query 'Reservations[0].Instances[0].PublicDnsName' \
  --output text)

echo "Host: $INSTANCE_DNS"
echo "User: ec2-user"
echo "Key: ~/.ssh/nf-core-vscode-server.pem"
```

### 3. Configure SSH Config (Optional but Recommended)

Add an entry to your `~/.ssh/config` file:

```
Host nf-core-dev
    HostName <INSTANCE_PUBLIC_DNS>
    User ec2-user
    IdentityFile ~/.ssh/nf-core-vscode-server.pem
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

Replace `<INSTANCE_PUBLIC_DNS>` with the actual DNS name from step 2.

### 4. Connect with VS Code or Kiro

**Using VS Code or Kiro:**
1. Ensure the "Remote - SSH" extension is installed
2. Press `Cmd+Shift+P` (Mac) or `Ctrl+Shift+P` (Windows/Linux)
3. Type "Remote-SSH: Connect to Host"
4. Select "VSCodeServer" (if using quick setup) or "nf-core-dev" (if using manual setup)
5. VS Code or Kiro will connect and you can open your workspace to develop. 

> [!IMPORTANT]
> When you connect remotely, VSCode starts a new VSCode server process! You will need to install your extensions (like the `nf-core-extensionpack`) on the remote VSCode server. 
> 
> Once you connect to the remote server in VSCode or Kiro, click the Extensions icon in the Activity Bar on the side of VS Code, or use the shortcut `Ctrl+Shift+X`. The browse for extensions you want to install on the remote server. 

### 5. Terminal SSH (Alternative)

For command-line access:

**Quick setup:**
```bash
ssh VSCodeServer
```

**Manual setup:**
```bash
ssh -i ~/.ssh/nf-core-vscode-server.pem ec2-user@<INSTANCE_PUBLIC_DNS>
# or if using SSH config:
ssh nf-core-dev
```

### Benefits of Remote SSH

- **Native performance**: Run code directly on the EC2 instance
- **Full extension support**: All VS Code/Kiro extensions work remotely
- **File system access**: Direct access to instance files
- **Terminal integration**: Run commands in the remote environment
- **Port forwarding**: Access services running on the instance
- **AI assistance**: Kiro can help with code on the remote instance

## Configuration Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| VSCodeUser | Linux username for VS Code Server | `ec2-user` |
| GitUserName | Global Git user.name for commits | `Anonymous` |
| GitUserEmail | Global Git user.email for commits | `user@example.com` |
| TowerAccessToken | Seqera Tower access token | (empty) |
| GithubAccessToken | GitHub personal access token | (empty) |
| InstanceName | EC2 instance name tag | `VSCodeServer` |
| InstanceVolumeSize | EBS volume size in GB | `100` |
| InstanceType | EC2 instance type | `m7g.2xlarge` |
| InstanceOperatingSystem | Operating system | `AmazonLinux-2023` |
| HomeFolder | VS Code Server home folder | `/workdir` |
| DevServerBasePath | Application base path for Nginx | `app` |
| DevServerPort | Application port | `8081` |
| RepoUrl | Git repository to clone on startup | `https://github.com/nf-core/rnaseq.git` |
| MyIPCidrRange | CIDR range for SSH access | `0.0.0.0/0` |

## Pre-installed Software

- **Nextflow**: Latest version (direct binary installation)
- **Docker**: With Amazon ECR credential helper
- **Miniconda**: Python environment manager (configured for bioconda/conda-forge)
- **AWS CLI**: Latest version
- **GitHub CLI**: Latest version
- **Git**: Latest version
- **OpenJDK**: Version 21 (Amazon Corretto)
- **Development Tools**: GCC, make, and build essentials
- **VS Code Extensions**:
  - AWS Toolkit
  - Live Server
  - Auto Run Command
  - Nextflow
  - nf-core Extension Pack

## Post-Deployment Setup

### Install nf-core Tools (Optional)

The nf-core tools are not installed during deployment to reduce setup time. To install them after connecting to your instance:

```bash
# SSH into your instance or open a terminal in VS Code/Kiro
conda install -y nf-core

# Verify installation
nf-core --version
```

This typically takes 5-10 minutes. The conda environment is already configured with bioconda and conda-forge channels.

## Instance Types

Recommended instance types (7th/8th generation C or M series):

**Graviton (ARM-based):**
- `m7g.large` - 2 vCPU, 8 GB RAM (budget)
- `m7g.xlarge` - 4 vCPU, 16 GB RAM
- `m7g.2xlarge` - 8 vCPU, 32 GB RAM (default)
- `c7g.2xlarge` - 8 vCPU, 16 GB RAM (compute-optimized)

**x86-based:**
- `m7i.large` - 2 vCPU, 8 GB RAM (budget)
- `m7i.xlarge` - 4 vCPU, 16 GB RAM
- `m7i.2xlarge` - 8 vCPU, 32 GB RAM
- `c7i.2xlarge` - 8 vCPU, 16 GB RAM (compute-optimized)

## Update Stack

To update an existing stack:

1. Edit `cfn-stack-parameters.yaml` with your new values
2. Run the deployment script again:

```bash
./deploy.sh
```

The script automatically detects if the stack exists and performs an update instead of creating a new stack.

**Manual update** (alternative):

```bash
aws cloudformation update-stack \
  --stack-name nf-core-vscode-server \
  --template-body file://nf-core-vscode-server-ssh.yaml \
  --parameters \
    ParameterKey=InstanceType,ParameterValue=m7g.xlarge \
  --capabilities CAPABILITY_IAM
```

## Delete Stack

To remove all resources, run the cleanup script:

```bash
./cleanup.sh
```

**Using a custom parameters file:**

```bash
# Use a different parameters file
./cleanup.sh -p my-custom-params.yaml

# Or using the long form
./cleanup.sh --param-file production-params.yaml
```

**Command line options:**
- `-p, --param-file FILE`: Specify CloudFormation parameters file (default: `cfn-stack-parameters.yaml`)
- `-h, --help`: Show help message

The script will:
- Read stack configuration from the specified parameters file
- Display all resources that will be deleted
- Prompt for confirmation (requires typing stack name)
- Delete the CloudFormation stack
- Monitor deletion progress with real-time updates
- Clean up local files (stack-outputs.txt, SSH keys)

**Environment-specific cleanup:**

```bash
# Clean up development environment
./cleanup.sh -p dev-params.yaml

# Clean up production environment  
./cleanup.sh -p prod-params.yaml
```

If the parameters file is not found, the script will show help information and exit. 

**Manual deletion** (alternative):

You can use the AWS CLI to delete the CloudFormation stack manually. Assuming that you named the stack `nf-core-vscode-server`: 

```bash
aws cloudformation delete-stack --stack-name nf-core-vscode-server
```

Monitor deletion:

```bash
aws cloudformation wait stack-delete-complete --stack-name nf-core-vscode-server
```

**Important:** Deletion will permanently remove:
- EC2 instance and all data on it
- CloudFront distribution
- Security groups
- IAM roles and instance profiles
- Secrets Manager secrets
- SSH key pairs
- CloudWatch logs

**Important**: 

This script will **NOT** delete the uploaded CloudFormation template in your S3 bucket**. You will need to do that manually. 

## Troubleshooting

### Check SSM Document Execution

View bootstrap logs:

```bash
aws logs tail /aws/ssm/VSCodeSSMDoc --follow
```

### Check Instance Status

```bash
aws ec2 describe-instance-status \
  --instance-ids $(aws cloudformation describe-stack-resources \
    --stack-name nf-core-vscode-server \
    --logical-resource-id VSCodeInstance \
    --query 'StackResources[0].PhysicalResourceId' \
    --output text)
```

### Connect to Instance via Session Manager

```bash
INSTANCE_ID=$(aws cloudformation describe-stack-resources \
  --stack-name nf-core-vscode-server \
  --logical-resource-id VSCodeInstance \
  --query 'StackResources[0].PhysicalResourceId' \
  --output text)

aws ssm start-session --target $INSTANCE_ID
```

### Common Issues

**Stack creation fails:**
- Check CloudFormation events for specific error messages
- Verify you have sufficient EC2 instance limits in your region
- Ensure IAM permissions are correct

**Cannot access VS Code Server:**
- Wait for health check to complete (check stack outputs)
- Verify CloudFront distribution is deployed
- Check security group rules

**SSH connection refused:**
- Ensure SSH key permissions are set to 400
- Verify your IP is allowed in MyIPCidrRange parameter
- Check instance is running

## Security Considerations

- The instance has AdministratorAccess IAM permissions for development purposes
- SSH access is controlled via MyIPCidrRange parameter (default: 0.0.0.0/0)
- VS Code Server is password-protected
- CloudFront provides an additional layer of security
- Secrets are stored in AWS Secrets Manager

**For production use:**
- Restrict MyIPCidrRange to your specific IP/CIDR
- Consider using AWS VPN or Direct Connect
- Review and restrict IAM permissions
- Enable CloudWatch logging and monitoring

## Cost Estimation

Approximate monthly costs (us-east-1):
- EC2 m7g.2xlarge: ~$120/month
- EBS gp3 100GB: ~$8/month
- CloudFront: ~$1-5/month (depending on usage)
- Data transfer: Variable

**Cost optimization:**
- Use smaller instance types for light workloads
- Stop instance when not in use
- Use Graviton instances (better price/performance)

## Support

For issues related to:
- **Template**: Check CloudFormation events and SSM logs
- **Nextflow**: Visit [nf-core documentation](https://nf-co.re/)
- **VS Code Server**: Visit [code-server documentation](https://coder.com/docs/code-server)

## License

This template is provided as-is for development purposes.
