#------------------------------------------------------
# Setup important variables
#------------------------------------------------------
# SCRIPT DIRECTORY
SCRIPT_DIRECTORY=$(pwd)
# Secret file location
SECRET_FILE="$SCRIPT_DIRECTORY/py_crawler/secrets/accesstoken"

#------------------------------------------------------
# Confirm env variable (if run from doocker) is present
#------------------------------------------------------
# Directory where we will install the Playbooks site from github
if [ -v PLAYBOOKS_DIR ]; then
  echo "Playbooks Directory set by docker to $PLAYBOOKS_DIR"
else
  echo "No \$PLAYBOOKS_DIR set. Setting to ../PLAYBOOKS_REPO"
  PLAYBOOKS_DIR="../PLAYBOOKS_REPO"
fi

# Directory where we will keep the output of the command
if [ -v OUTPUT_DIR ]; then
  echo "Playbooks Directory set by docker to $OUTPUT_DIR"
else
  echo "No \$OUTPUT_DIR set. Setting to ../OUTPUT"
  OUTPUT_DIR="../OUTPUT"
fi


#------------------------------------------------------
# Run py_crawler
#------------------------------------------------------
poetry run python -m py_crawler

#------------------------------------------------------
# Update Playbooks site with new artifacts
#------------------------------------------------------

#------------------------------------------------------
# Confirm secret is present
#------------------------------------------------------
if test -f "$SECRET_FILE"; then
  # Set Access Token
  GH_TOKEN=$(cat "$SECRET_FILE")
else
  echo No secret file present at $SECRET_FILE
fi

#------------------------------------------------------
# Set up GIT Variables
#------------------------------------------------------
# GIT REPO URL
PLAYBOOKS_REPO="Credentive-Sec/ficam-playbooks"
# BRANCH FOR THIS RUN
BRANCH=$(date +%m%d)-fpki-graph-update

if ! test -d $PLAYBOOKS_DIR; then
    # If the playbooks site doesn't exist here, create it
    echo "Setting \$PLAYBOOKS_DIR to $PLAYBOOKS_DIR"
    mkdir $PLAYBOOKS_DIR
fi

(
  echo "Executing gh auth login"
  echo $GH_TOKEN | gh auth login --with-token
  gh auth setup-git
  cd "$PLAYBOOKS_DIR" || { echo "Playbooks directory does not exist!"; exit; }

  # See if we've already initialized the git repo here
  if [ "$(git rev-parse --is-inside-work-tree)" = "true" ]; then
    # sync the repo
    echo "Repo found. Syncing..."
    gh repo sync --force
  else
    # initialize and update the repo
    echo "Initializing the playbooks REPO"
    gh repo clone $PLAYBOOKS_REPO .
    gh repo set-default $PLAYBOOKS_REPO
    git config user.name "py-crawler"
    git config user.email "robert.sherwood@credentive.com"
  fi

  echo "Checking for local branch for the current run"
  if [ "$(git branch --list $BRANCH)" = "" ]; then
    # Create a branch for this run
    echo "Creating a branch for the current Run"
    git checkout -B "$BRANCH"
  else
    echo "Branch exists. Switching..."
    git switch $BRANCH
  fi

  # Update the site with the new artifacts
  echo "Updating site with new artifacts"
  cp "$OUTPUT_DIR/CACertificatesValidatingToFederalCommonPolicyG2.p7b" _fpki/tools/
  cp "$OUTPUT_DIR/fpki-certs.gexf" _fpki/tools/
  sed -e "s/\*\*Last Update\*\*: .*/\*\*Last Update\*\*: $(date +"%B %d, %Y")/" _fpki/tools/fpki_tools_graph.md > _fpki/tools/fpki_tools_graph.tmp
  mv _fpki/tools/fpki_tools_graph.tmp _fpki/tools/fpki_tools_graph.md

  # Check for open PR
  # OPEN_PR=$(gh pr list --head $(date +%m%d)-fpki-graph-update --json number)

  # Submit the playbooks updates to the git repo
  echo "Adding and commiting updates"
  git add -A
  git commit -m "automatic crawler update"
  echo "Submitting updates to origin"
  git push --all

  # Create Issue, record the output to a variable
  echo "Creating Issue"
  ISSUE=$(gh issue create --repo "$PLAYBOOKS_REPO" --title "$(date +%m%d) FPKI Graph Update"  --body "Automatically Created")

  # Parse out the issue number
  ISSUE_NUM=$(echo $ISSUE | cut -f 7 -d "/")

  # Open a PR linked to the Issue
  echo "Creating PR"
  gh pr create --repo "$PLAYBOOKS_REPO" --head "$BRANCH" --base "staging" --title "$(date +%m%d) Fpki Graph Update" --body "Linked to Issue #$ISSUE_NUM"
)