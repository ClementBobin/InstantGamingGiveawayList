#!/bin/bash

# Environment variables for authentication
export GITHUB_TOKEN="your_github_token"
export AZURE_DEVOPS_TOKEN="your_azure_devops_token"
export AZURE_DEVOPS_ORG="your_azure_devops_organization"
export AZURE_DEVOPS_PROJECT="your_azure_devops_project"
MAPPING_FILE="mapping.json"

# Initialize the mapping file if it doesn't exist
if [ ! -f "$MAPPING_FILE" ]; then
    echo '{"mappings":{}}' > "$MAPPING_FILE"
fi

# Fetch discussions from a GitHub repository
fetch_github_discussions() {
    local repo=$1
    curl -s -H "Authorization: token $GITHUB_TOKEN" \
         -H "Accept: application/vnd.github.elektra-preview+json" \
         "https://api.github.com/repos/$repo/discussions"
}

# Fetch issues from a GitHub repository
fetch_github_issues() {
    local repo=$1
    curl -s -H "Authorization: token $GITHUB_TOKEN" \
         "https://api.github.com/repos/$repo/issues"
}

# Fetch work items (tasks, user stories, etc.) from Azure DevOps
fetch_azure_devops_work_items() {
    local project=$1
    curl -s -u ":$AZURE_DEVOPS_TOKEN" \
         "https://dev.azure.com/$AZURE_DEVOPS_ORG/$project/_apis/wit/workitems?api-version=6.0"
}

# Fetch sprints from Azure DevOps
fetch_azure_devops_sprints() {
    local project=$1
    curl -s -u ":$AZURE_DEVOPS_TOKEN" \
         "https://dev.azure.com/$AZURE_DEVOPS_ORG/$project/_apis/work/teamsettings/iterations?api-version=6.0"
}

# Fetch Azure DevOps users to map GitHub users to Azure DevOps users for attribution
fetch_azure_devops_users() {
    curl -s -u ":$AZURE_DEVOPS_TOKEN" \
         "https://dev.azure.com/$AZURE_DEVOPS_ORG/_apis/graph/users?api-version=6.0-preview.1"
}

# Create a work item (e.g., Task, User Story) in Azure DevOps with tags and attribution
create_azure_devops_work_item() {
    local project=$1
    local type=$2
    local title=$3
    local description=$4
    local tags=$5
    local assigned_to=$6
    curl -s -X POST -u ":$AZURE_DEVOPS_TOKEN" \
         -H "Content-Type: application/json-patch+json" \
         -d "[{\"op\":\"add\", \"path\":\"/fields/System.Title\", \"value\":\"$title\"}, 
              {\"op\":\"add\", \"path\":\"/fields/System.Description\", \"value\":\"$description\"},
              {\"op\":\"add\", \"path\":\"/fields/System.Tags\", \"value\":\"$tags\"},
              {\"op\":\"add\", \"path\":\"/fields/System.AssignedTo\", \"value\":\"$assigned_to\"}]" \
         "https://dev.azure.com/$AZURE_DEVOPS_ORG/$project/_apis/wit/workitems/\$${type}?api-version=6.0"
}

# Update a work item in Azure DevOps with tags and attribution
update_azure_devops_work_item() {
    local work_item_id=$1
    local title=$2
    local description=$3
    local tags=$4
    local assigned_to=$5
    curl -s -X PATCH -u ":$AZURE_DEVOPS_TOKEN" \
         -H "Content-Type: application/json-patch+json" \
         -d "[{\"op\":\"replace\", \"path\":\"/fields/System.Title\", \"value\":\"$title\"}, 
              {\"op\":\"replace\", \"path\":\"/fields/System.Description\", \"value\":\"$description\"},
              {\"op\":\"replace\", \"path\":\"/fields/System.Tags\", \"value\":\"$tags\"},
              {\"op\":\"replace\", \"path\":\"/fields/System.AssignedTo\", \"value\":\"$assigned_to\"}]" \
         "https://dev.azure.com/$AZURE_DEVOPS_ORG/_apis/wit/workitems/$work_item_id?api-version=6.0"
}

# Create a GitHub issue with labels
create_github_issue() {
    local repo=$1
    local title=$2
    local body=$3
    local labels=$4
    curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
         -d "{\"title\":\"$title\", \"body\":\"$body\", \"labels\": $labels}" \
         "https://api.github.com/repos/$repo/issues"
}

# Update a GitHub issue with labels
update_github_issue() {
    local repo=$1
    local issue_number=$2
    local title=$3
    local body=$4
    local labels=$5
    curl -s -X PATCH -H "Authorization: token $GITHUB_TOKEN" \
         -d "{\"title\":\"$title\", \"body\":\"$body\", \"labels\": $labels}" \
         "https://api.github.com/repos/$repo/issues/$issue_number"
}

# Update mapping between GitHub and Azure DevOps
update_mapping() {
    local github_id=$1
    local azure_id=$2
    jq --arg github_id "$github_id" --arg azure_id "$azure_id" '.mappings[$github_id] = $azure_id' "$MAPPING_FILE" > tmp.$$.json && mv tmp.$$.json "$MAPPING_FILE"
}

# Get Azure DevOps ID for a GitHub issue/discussion
get_azure_id_for_github() {
    local github_id=$1
    jq -r --arg github_id "$github_id" '.mappings[$github_id]' "$MAPPING_FILE"
}

# Main sync function
sync_github_and_azure_devops() {
    local github_repo=$1
    local azure_project=$2
    
    # Fetch GitHub issues and Azure DevOps work items
    github_issues=$(fetch_github_issues "$github_repo")
    azure_work_items=$(fetch_azure_devops_work_items "$azure_project")

    # Loop through GitHub issues and sync with Azure DevOps
    for issue in $(echo "$github_issues" | jq -r '.[] | @base64'); do
        _jq() {
            echo "$issue" | base64 --decode | jq -r "$1"
        }

        github_id=$(_jq '.id')
        title=$(_jq '.title')
        body=$(_jq '.body')
        labels=$(echo $(_jq '.labels | map(.name)') | jq -c '.')
        assigned_to=$(_jq '.assignee.login')

        # Check if this issue exists in Azure DevOps
        azure_id=$(get_azure_id_for_github "$github_id")

        if [ -z "$azure_id" ]; then
            # Create a new work item in Azure DevOps
            new_azure_id=$(create_azure_devops_work_item "$azure_project" "Task" "$title" "$body" "$labels" "$assigned_to" | jq -r '.id')
            update_mapping "$github_id" "$new_azure_id"
        else
            # Update existing Azure DevOps work item
            update_azure_devops_work_item "$azure_id" "$title" "$body" "$labels" "$assigned_to"
        fi
    done

    # Fetch work items from Azure DevOps and sync with GitHub
    for work_item in $(echo "$azure_work_items" | jq -r '.value[] | @base64'); do
        _jq() {
            echo "$work_item" | base64 --decode | jq -r "$1"
        }

        azure_id=$(_jq '.id')
        title=$(_jq '.fields["System.Title"]')
        description=$(_jq '.fields["System.Description"]')
        tags=$(_jq '.fields["System.Tags"]')
        assigned_to=$(_jq '.fields["System.AssignedTo"]')

        # Check if this work item exists in GitHub
        github_id=$(jq -r --arg azure_id "$azure_id" '.mappings | to_entries[] | select(.value == $azure_id) | .key' "$MAPPING_FILE")

        if [ -z "$github_id" ]; then
            # Create a new issue in GitHub
            new_github_id=$(create_github_issue "$github_repo" "$title" "$description" "$tags" | jq -r '.id')
            update_mapping "$new_github_id" "$azure_id"
        else
            # Update existing GitHub issue
            update_github_issue "$github_repo" "$github_id" "$title" "$description" "$tags"
        fi
    done
}

# Run the sync
GITHUB_REPO="your_github_org/your_github_repo"
AZURE_PROJECT="your_azure_project"
sync_github_and_azure_devops "$GITHUB_REPO" "$AZURE_PROJECT"
