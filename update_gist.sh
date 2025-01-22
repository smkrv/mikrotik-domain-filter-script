#!/bin/bash

# Constants for connection (replace with your own values)
GITHUB_TOKEN="your_github_token"  # Personal access token
GIST_ID="your_gist_id"  # ID of the specific Gist
FILENAME="filtered_domains_mikrotik.txt"  # Name of the file in the Gist
LOCAL_FILE_PATH="/path/to/your/local/filtered_domains_mikrotik.txt"  # Path to the local file

# Check for required utilities
command -v curl >/dev/null 2>&1 || { echo "curl is required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }

# Read content from the local file
NEW_CONTENT=$(cat "$LOCAL_FILE_PATH")

# Update the Gist (complete content replacement)
RESPONSE=$(curl -s -X PATCH \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    -d "{
        \"files\": {
            \"$FILENAME\": {
                \"content\": $(echo "$NEW_CONTENT" | jq -R -s .)
            }
        }
    }" \
    "https://api.github.com/gists/$GIST_ID")

# Check the result
if echo "$RESPONSE" | jq -e '.id' > /dev/null; then
    echo "✅ File fully replaced in Gist"
else
    echo "❌ Error updating Gist"
    echo "$RESPONSE"
    exit 1
fi
