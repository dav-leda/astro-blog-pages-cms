#!/bin/bash

# Git Synchronization Script
# This script synchronizes local and remote git versions

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not a git repository! Please run this script from within a git repository."
        exit 1
    fi
}

# Function to get current branch name
get_current_branch() {
    git branch --show-current
}

# Function to check if there are uncommitted changes
has_uncommitted_changes() {
    ! git diff-index --quiet HEAD --
}

# Function to check if there are untracked files
has_untracked_files() {
    [ -n "$(git ls-files --others --exclude-standard)" ]
}

# Function to stash changes if needed
stash_changes() {
    if has_uncommitted_changes || has_untracked_files; then
        print_warning "Found uncommitted changes or untracked files. Stashing them..."
        git add -A
        git stash push -m "Auto-stash before sync - $(date)"
        echo "stashed"
    else
        echo "none"
    fi
}

# Function to pop stashed changes
pop_stash() {
    if [ "$1" = "stashed" ]; then
        print_status "Restoring stashed changes..."
        git stash pop
        print_success "Stashed changes restored."
    fi
}

# Function to handle merge conflicts
handle_merge_conflicts() {
    if git status --porcelain | grep -q "^UU\|^AA\|^DD"; then
        print_error "Merge conflicts detected!"
        print_status "Please resolve conflicts manually and run: git add . && git commit"
        print_status "Then run this script again."
        exit 1
    fi
}

# Main synchronization function
sync_git() {
    local branch=$(get_current_branch)
    local remote="origin"
    
    print_status "Starting git synchronization on branch: $branch"
    
    # Check if we're in a git repository
    check_git_repo
    
    # Fetch latest changes from remote
    print_status "Fetching latest changes from remote..."
    git fetch $remote
    
    # Check if remote branch exists
    if ! git show-ref --verify --quiet refs/remotes/$remote/$branch; then
        print_warning "Remote branch $remote/$branch doesn't exist. Pushing current branch..."
        git push -u $remote $branch
        print_success "Branch pushed to remote successfully!"
        return 0
    fi
    
    # Check the status compared to remote
    local behind=$(git rev-list --count HEAD..$remote/$branch)
    local ahead=$(git rev-list --count $remote/$branch..HEAD)
    
    print_status "Local branch is $ahead commits ahead and $behind commits behind remote"
    
    if [ $behind -eq 0 ] && [ $ahead -eq 0 ]; then
        print_success "Already up to date! No synchronization needed."
        return 0
    fi
    
    # Stash uncommitted changes if any
    local stash_status=$(stash_changes)
    
    if [ $behind -eq 0 ] && [ $ahead -gt 0 ]; then
        # Only local changes - simple push
        print_status "Only local changes found. Pushing changes..."
        if [ "$FORCE" = true ]; then
            print_warning "Force pushing changes..."
            git push $remote $branch --force
        else
            git push $remote $branch
        fi
        print_success "Successfully pushed local changes!"
        
    elif [ $behind -gt 0 ] && [ $ahead -eq 0 ]; then
        # Only remote changes - simple pull
        print_status "Only remote changes found. Pulling changes..."
        if [ "$REBASE" = true ]; then
            git pull $remote $branch --rebase
        else
            git pull $remote $branch
        fi
        print_success "Successfully pulled remote changes!"
        
    else
        # Both local and remote changes - merge or rebase required
        if [ "$REBASE" = true ]; then
            print_status "Both local and remote changes found. Rebasing..."
            
            # Try to rebase
            if git pull $remote $branch --rebase; then
                print_success "Successfully rebased remote changes!"
                
                # Push the rebased changes
                print_status "Pushing rebased changes..."
                git push $remote $branch
                print_success "Successfully pushed rebased changes!"
                
            else
                print_error "Rebase failed! Please resolve conflicts manually."
                print_status "Use 'git rebase --continue' after resolving conflicts"
                print_status "Or use 'git rebase --abort' to cancel the rebase"
                # Restore stashed changes even on failure
                pop_stash $stash_status
                exit 1
            fi
        else
            print_status "Both local and remote changes found. Merging..."
            
            # Try to merge (this might open an editor for merge commit)
            if git pull $remote $branch --no-rebase --no-edit; then
                print_success "Successfully merged remote changes!"
                
                # Check for merge conflicts
                handle_merge_conflicts
                
                # Push the merge
                print_status "Pushing merged changes..."
                git push $remote $branch
                print_success "Successfully pushed merged changes!"
                
            else
                print_error "Merge failed! Please resolve conflicts manually."
                # Restore stashed changes even on failure
                pop_stash $stash_status
                exit 1
            fi
        fi
    fi
    
    # Restore stashed changes if any
    pop_stash $stash_status
    
    print_success "Git synchronization completed successfully!"
}

# Function to show help
show_help() {
    echo "Git Synchronization Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -f, --force    Force push (use with caution - overwrites remote)"
    echo "  -r, --rebase   Use rebase instead of merge (creates linear history)"
    echo ""
    echo "This script will:"
    echo "  1. Fetch latest changes from remote"
    echo "  2. Stash any uncommitted changes"
    echo "  3. Synchronize local and remote branches"
    echo "  4. Restore stashed changes"
    echo ""
    echo "When to use --rebase:"
    echo "  • Working on feature branches"
    echo "  • Want clean, linear history"
    echo "  • Personal/local branches not shared with others"
    echo ""
    echo "When to use merge (default):"
    echo "  • Working on main/master branch"
    echo "  • Collaborating with team"
    echo "  • Want to preserve complete history"
    echo ""
    echo "When to use --force:"
    echo "  • After rebasing and need to update remote"
    echo "  • DANGER: This overwrites remote history!"
    echo ""
}

# Parse command line arguments
FORCE=false
REBASE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -r|--rebase)
            REBASE=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    echo "================================================"
    echo "           Git Synchronization Script"
    echo "================================================"
    echo ""
    
    # Run the synchronization
    sync_git
    
    echo ""
    echo "================================================"
    echo "           Synchronization Complete"
    echo "================================================"
}

# Run main function
main "$@"
# Test comment
