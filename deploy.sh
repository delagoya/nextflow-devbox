#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_PARAMS_FILE="cfn-stack-parameters.yaml"
TEMPLATE_FILE="nf-core-vscode-server-ssh.yaml"

# Function to print colored messages
print_info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Parse command line arguments
PARAMS_FILE="$DEFAULT_PARAMS_FILE"

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -p, --param-file FILE    CloudFormation parameters file (default: cfn-stack-parameters.yaml)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use default parameters file"
    echo "  $0 -p dev-params.yaml                # Use custom parameters file"
    echo "  $0 --param-file prod-params.yaml     # Use custom parameters file (long form)"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--param-file)
            PARAMS_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Function to check if required files exist
check_files() {
    print_info "Checking required files..."
    
    if [ ! -f "$PARAMS_FILE" ]; then
        print_error "Parameters file not found: $PARAMS_FILE"
        exit 1
    fi
    
    if [ ! -f "$TEMPLATE_FILE" ]; then
        print_error "Template file not found: $TEMPLATE_FILE"
        exit 1
    fi
    
    print_success "All required files found"
}

# Function to parse YAML parameters
parse_yaml() {
    local file=$1
    local prefix=$2
    local s='[[:space:]]*'
    local w='[a-zA-Z0-9_]*'
    local fs=$(echo @|tr @ '\034')
    
    sed -ne "s|^\($s\):|\1|" \
         -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
         -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p" $file |
    awk -F$fs '{
        indent = length($1)/2;
        vname[indent] = $2;
        for (i in vname) {if (i > indent) {delete vname[i]}}
        if (length($3) > 0) {
            vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
            printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
        }
    }'
}

# Function to read parameters from YAML
read_parameters() {
    print_info "Reading parameters from $PARAMS_FILE..."
    
    # Parse YAML file
    eval $(parse_yaml "$PARAMS_FILE" "CFN_")
    
    # Extract stack name and region
    STACK_NAME="${CFN_StackName}"
    REGION="${CFN_Region}"
    
    if [ -z "$STACK_NAME" ]; then
        print_error "StackName not found in parameters file"
        exit 1
    fi
    
    if [ -z "$REGION" ]; then
        print_warning "Region not specified, using default: us-east-1"
        REGION="us-east-1"
    fi
    
    print_success "Stack Name: $STACK_NAME"
    print_success "Region: $REGION"
}

# Function to get current public IP
get_current_ip() {
    print_info "Getting current public IP address..."
    
    # Try multiple services in case one is down
    CURRENT_IP=""
    
    # Try AWS checkip service first
    CURRENT_IP=$(curl -s --connect-timeout 5 checkip.amazonaws.com 2>/dev/null | tr -d '\n')
    
    if [ -z "$CURRENT_IP" ]; then
        # Fallback to other services
        CURRENT_IP=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null | tr -d '\n')
    fi
    
    if [ -z "$CURRENT_IP" ]; then
        CURRENT_IP=$(curl -s --connect-timeout 5 ipinfo.io/ip 2>/dev/null | tr -d '\n')
    fi
    
    # Validate IP format (basic check)
    if [[ $CURRENT_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # Add /32 for single IP CIDR
        CURRENT_IP_CIDR="${CURRENT_IP}/32"
        print_success "Current IP: $CURRENT_IP"
        print_success "CIDR Range: $CURRENT_IP_CIDR"
    else
        print_error "Failed to get valid IP address from external services"
        print_warning "Using 0.0.0.0/0 (open to all IPs) - NOT RECOMMENDED for production"
        CURRENT_IP_CIDR="0.0.0.0/0"
    fi
}

# Function to build CloudFormation parameters
build_cfn_parameters() {
    print_info "Building CloudFormation parameters..."
    
    # Get current IP automatically
    get_current_ip
    
    # Show user what IP will be used for security
    echo ""
    print_info "Security Configuration:"
    echo "  SSH access will be restricted to: $CURRENT_IP_CIDR"
    echo ""
    
    CFN_PARAMS=""
    
    # Add each parameter if it exists and is not empty
    [ -n "$CFN_Parameters_VSCodeUser" ] && CFN_PARAMS+="ParameterKey=VSCodeUser,ParameterValue=\"$CFN_Parameters_VSCodeUser\" "
    [ -n "$CFN_Parameters_GitUserName" ] && CFN_PARAMS+="ParameterKey=GitUserName,ParameterValue=\"$CFN_Parameters_GitUserName\" "
    [ -n "$CFN_Parameters_GitUserEmail" ] && CFN_PARAMS+="ParameterKey=GitUserEmail,ParameterValue=\"$CFN_Parameters_GitUserEmail\" "
    [ -n "$CFN_Parameters_TowerAccessToken" ] && CFN_PARAMS+="ParameterKey=TowerAccessToken,ParameterValue=\"$CFN_Parameters_TowerAccessToken\" "
    [ -n "$CFN_Parameters_GithubAccessToken" ] && CFN_PARAMS+="ParameterKey=GithubAccessToken,ParameterValue=\"$CFN_Parameters_GithubAccessToken\" "
    [ -n "$CFN_Parameters_InstanceName" ] && CFN_PARAMS+="ParameterKey=InstanceName,ParameterValue=\"$CFN_Parameters_InstanceName\" "
    [ -n "$CFN_Parameters_InstanceVolumeSize" ] && CFN_PARAMS+="ParameterKey=InstanceVolumeSize,ParameterValue=\"$CFN_Parameters_InstanceVolumeSize\" "
    [ -n "$CFN_Parameters_InstanceType" ] && CFN_PARAMS+="ParameterKey=InstanceType,ParameterValue=\"$CFN_Parameters_InstanceType\" "
    [ -n "$CFN_Parameters_InstanceOperatingSystem" ] && CFN_PARAMS+="ParameterKey=InstanceOperatingSystem,ParameterValue=\"$CFN_Parameters_InstanceOperatingSystem\" "
    [ -n "$CFN_Parameters_HomeFolder" ] && CFN_PARAMS+="ParameterKey=HomeFolder,ParameterValue=\"$CFN_Parameters_HomeFolder\" "
    [ -n "$CFN_Parameters_DevServerBasePath" ] && CFN_PARAMS+="ParameterKey=DevServerBasePath,ParameterValue=\"$CFN_Parameters_DevServerBasePath\" "
    [ -n "$CFN_Parameters_DevServerPort" ] && CFN_PARAMS+="ParameterKey=DevServerPort,ParameterValue=\"$CFN_Parameters_DevServerPort\" "
    [ -n "$CFN_Parameters_RepoUrl" ] && CFN_PARAMS+="ParameterKey=RepoUrl,ParameterValue=\"$CFN_Parameters_RepoUrl\" "
    # Use automatically detected IP instead of YAML parameter
    CFN_PARAMS+="ParameterKey=MyIPCidrRange,ParameterValue=\"$CURRENT_IP_CIDR\" "
    
    print_success "Parameters built successfully"
    # echo $CFN_PARAMS
}

# Function to check if stack exists
stack_exists() {
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        &>/dev/null
    return $?
}

# Function to deploy stack
deploy_stack() {
    if stack_exists; then
        print_warning "Stack $STACK_NAME already exists. Updating..."
        OPERATION="update-stack"
        ACTION="update"
    else
        print_info "Creating new stack: $STACK_NAME"
        OPERATION="create-stack"
        ACTION="create"
    fi
    
    print_info "Deploying CloudFormation stack..."
    
    # Check template size
    template_size=$(wc -c < "$TEMPLATE_FILE")
    
    if [ $template_size -gt 51200 ]; then
        print_warning "Template size ($template_size bytes) exceeds CloudFormation limit (51200 bytes)"
        print_info "Uploading template to S3..."
        
        # Get AWS Account ID
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Create S3 bucket for templates if it doesn't exist
        S3_BUCKET="cfn-templates-${AWS_ACCOUNT_ID}-${REGION}"
        
        # Try to create bucket (will fail silently if exists)
        if ! aws s3 ls "s3://${S3_BUCKET}" --region "$REGION" > /dev/null 2>&1; then
            aws s3 mb "s3://${S3_BUCKET}" --region "$REGION" > /dev/null 2>&1
            if [ $? -eq 0 ]; then
                print_success "Created S3 bucket: ${S3_BUCKET}"
            fi
        fi
        
        # Upload template with public read access
        S3_KEY="nf-core-vscode-server/$(date +%Y%m%d-%H%M%S)-${TEMPLATE_FILE}"
        aws s3 cp "$TEMPLATE_FILE" "s3://${S3_BUCKET}/${S3_KEY}" \
            --region "$REGION" \
            > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            print_success "Template uploaded to S3"
            TEMPLATE_PARAM="--template-url https://s3.${REGION}.amazonaws.com/${S3_BUCKET}/${S3_KEY}"
        else
            print_error "Failed to upload template to S3"
            exit 1
        fi
    else
        TEMPLATE_PARAM="--template-body file://$TEMPLATE_FILE"
    fi
    
    # Deploy the stack
    output=$(aws cloudformation $OPERATION \
        --stack-name "$STACK_NAME" \
        $TEMPLATE_PARAM \
        --parameters $CFN_PARAMS \
        --capabilities "CAPABILITY_IAM" \
        --region "$REGION" 2>&1)
    
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        print_success "Stack $ACTION initiated successfully"
    else
        print_error "Failed to $ACTION stack"
        echo "$output"
        exit 1
    fi
}

# Function to monitor stack progress
monitor_stack() {
    print_info "Monitoring stack progress (this may take 10-15 minutes)..."
    echo ""
    
    local last_event_time=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    local stack_status=""
    local final_status=""
    local last_status=""
    
    while true; do
        # Get current stack status
        stack_status=$(aws cloudformation describe-stacks \
            --stack-name "$STACK_NAME" \
            --region "$REGION" \
            --query 'Stacks[0].StackStatus' \
            --output text 2>/dev/null)

        # Get recent events
        events=$(aws cloudformation describe-stack-events \
            --stack-name "$STACK_NAME" \
            --region "$REGION" \
            --query "StackEvents[?Timestamp>\`$last_event_time\`].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId,ResourceStatusReason]" \
            --output text 2>/dev/null)
        
        # Display new events
        if [ -n "$events" ]; then
            while IFS=$'\t' read -r timestamp status type logical_id reason; do
                case "$status" in
                    *COMPLETE)
                        print_success "$logical_id ($type): $status"
                        ;;
                    *FAILED|*ROLLBACK*)
                        print_error "$logical_id ($type): $status"
                        [ -n "$reason" ] && echo "  Reason: $reason"
                        ;;
                    *IN_PROGRESS)
                        print_info "$logical_id ($type): $status"
                        ;;
                    *)
                        echo "  $logical_id ($type): $status"
                        ;;
                esac
                last_event_time="$timestamp"
            done <<< "$events"
        fi
        
        # Check if stack operation is complete
        case "$stack_status" in
            CREATE_COMPLETE|UPDATE_COMPLETE)
                final_status="success"
                break
                ;;
            CREATE_FAILED|UPDATE_FAILED|ROLLBACK_COMPLETE|UPDATE_ROLLBACK_COMPLETE|DELETE_COMPLETE)
                final_status="failed"
                break
                ;;
            "")
                print_error "Stack not found or unable to get status"
                exit 1
                ;;
        esac
        sleep 10
    done
    
    echo ""
    if [ "$final_status" = "success" ]; then
        print_success "Stack deployment completed successfully!"
        return 0
    else
        print_error "Stack deployment failed with status: $stack_status"
        return 1
    fi
}

# Function to display stack outputs
display_outputs() {
    print_info "Retrieving stack outputs..."
    echo ""
    
    outputs=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue,Description]' \
        --output text)
    
    if [ -n "$outputs" ]; then
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}                        STACK OUTPUTS                              ${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        while IFS=$'\t' read -r key value description; do
            echo -e "${BLUE}$key:${NC}"
            echo "  $value"
            [ -n "$description" ] && echo -e "  ${YELLOW}($description)${NC}"
            echo ""
        done <<< "$outputs"
        
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    else
        print_warning "No outputs available yet"
    fi
}

# Function to save outputs to file
save_outputs() {
    local output_file="stack-outputs.txt"
    
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs' \
        --output json > "$output_file"
    
    print_success "Outputs saved to $output_file"
}

# Main execution
main() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}        nf-core VS Code Server - CloudFormation Deployment         ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    print_info "Using parameters file: $PARAMS_FILE"
    echo ""
    
    # Check prerequisites
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Execute deployment steps
    check_files
    read_parameters
    build_cfn_parameters
    deploy_stack
    
    if monitor_stack; then
        display_outputs
        save_outputs
        
        echo ""
        print_success "Deployment complete! You can now access your VS Code Server."
        print_info "Next steps:"
        echo "  1. Open the URL from the outputs above"
        echo "  2. Use the password from the outputs to log in"
        echo "  3. Or set up Remote SSH following the README instructions"
        echo ""
    else
        print_error "Deployment failed. Check the CloudFormation console for details."
        echo "  Console: https://$REGION.console.aws.amazon.com/cloudformation/home?region=$REGION#/stacks"
        exit 1
    fi
}

# Run main function
main
