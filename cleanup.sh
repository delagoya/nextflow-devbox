#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PARAMS_FILE="cfn-stack-parameters.yaml"

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
    if [ -f "$PARAMS_FILE" ]; then
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
    else
        print_warning "Parameters file not found: $PARAMS_FILE"
        print_info "Please provide stack name and region manually"
        
        read -p "Enter stack name: " STACK_NAME
        read -p "Enter region [us-east-1]: " REGION
        REGION=${REGION:-us-east-1}
        
        if [ -z "$STACK_NAME" ]; then
            print_error "Stack name is required"
            exit 1
        fi
    fi
}

# Function to check if stack exists
stack_exists() {
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        &>/dev/null
    return $?
}

# Function to get stack resources
get_stack_resources() {
    print_info "Retrieving stack resources..."
    
    resources=$(aws cloudformation describe-stack-resources \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'StackResources[*].[ResourceType,LogicalResourceId]' \
        --output text 2>/dev/null)
    
    if [ -n "$resources" ]; then
        echo ""
        print_warning "The following resources will be deleted:"
        echo ""
        while IFS=$'\t' read -r type logical_id; do
            echo "  • $logical_id ($type)"
        done <<< "$resources"
        echo ""
    fi
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    print_warning "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_warning "                        WARNING                                    "
    print_warning "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    print_warning "This will permanently delete the stack: $STACK_NAME"
    print_warning "All resources including the EC2 instance and data will be removed."
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        print_info "Deletion cancelled"
        exit 0
    fi
    
    echo ""
    read -p "Type the stack name to confirm: " confirm_name
    
    if [ "$confirm_name" != "$STACK_NAME" ]; then
        print_error "Stack name does not match. Deletion cancelled."
        exit 1
    fi
}

# Function to delete stack
delete_stack() {
    print_info "Initiating stack deletion..."
    
    aws cloudformation delete-stack \
        --stack-name "$STACK_NAME" \
        --region "$REGION"
    
    if [ $? -eq 0 ]; then
        print_success "Stack deletion initiated"
    else
        print_error "Failed to initiate stack deletion"
        exit 1
    fi
}

# Function to monitor deletion progress
monitor_deletion() {
    print_info "Monitoring deletion progress..."
    echo ""
    
    local last_event_time=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    local stack_status=""
    
    while true; do
        # Get current stack status
        stack_status=$(aws cloudformation describe-stacks \
            --stack-name "$STACK_NAME" \
            --region "$REGION" \
            --query 'Stacks[0].StackStatus' \
            --output text 2>/dev/null)
        
        # If stack no longer exists, deletion is complete
        if [ $? -ne 0 ] || [ -z "$stack_status" ]; then
            print_success "Stack deleted successfully!"
            return 0
        fi
        
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
                    *DELETE_COMPLETE)
                        print_success "$logical_id ($type): $status"
                        ;;
                    *DELETE_FAILED)
                        print_error "$logical_id ($type): $status"
                        [ -n "$reason" ] && echo "  Reason: $reason"
                        ;;
                    *DELETE_IN_PROGRESS)
                        print_info "$logical_id ($type): $status"
                        ;;
                    *)
                        echo "  $logical_id ($type): $status"
                        ;;
                esac
                last_event_time="$timestamp"
            done <<< "$events"
        fi
        
        # Check if deletion failed
        if [ "$stack_status" = "DELETE_FAILED" ]; then
            print_error "Stack deletion failed!"
            print_info "Some resources may need to be manually deleted"
            print_info "Check the CloudFormation console for details:"
            echo "  https://$REGION.console.aws.amazon.com/cloudformation/home?region=$REGION#/stacks"
            return 1
        fi
        
        sleep 5
    done
}

# Function to cleanup local files
cleanup_local_files() {
    print_info "Cleaning up local files..."
    
    if [ -f "stack-outputs.txt" ]; then
        rm -f stack-outputs.txt
        print_success "Removed stack-outputs.txt"
    fi
    
    # Ask about SSH key
    if [ -f "$HOME/.ssh/nf-core-vscode-server.pem" ]; then
        echo ""
        read -p "Remove SSH key (~/.ssh/nf-core-vscode-server.pem)? (yes/no): " remove_key
        if [ "$remove_key" = "yes" ]; then
            rm -f "$HOME/.ssh/nf-core-vscode-server.pem"
            print_success "Removed SSH key"
        fi
    fi
    
    # Ask about SSH config entry
    if [ -f "$HOME/.ssh/config" ] && grep -q "Host nf-core-dev" "$HOME/.ssh/config"; then
        echo ""
        print_warning "Found SSH config entry for 'nf-core-dev'"
        print_info "You may want to manually remove it from ~/.ssh/config"
    fi
}

# Main execution
main() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}        nf-core VS Code Server - Stack Cleanup                     ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Check prerequisites
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Execute cleanup steps
    read_parameters
    
    # Check if stack exists
    if ! stack_exists; then
        print_error "Stack '$STACK_NAME' does not exist in region '$REGION'"
        exit 1
    fi
    
    get_stack_resources
    confirm_deletion
    delete_stack
    
    echo ""
    if monitor_deletion; then
        cleanup_local_files
        
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        print_success "Cleanup complete!"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
    else
        print_error "Cleanup encountered errors. Please check the CloudFormation console."
        exit 1
    fi
}

# Run main function
main
