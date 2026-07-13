echo "Type in your first and last name (no accent or special characters - e.g. 'ç'): "
read full_name

echo "Type in your email address (the one used for your GitHub account): "
read email

git config --global user.email "$email"
git config --global user.name "$full_name"
git config --global credential.helper osxkeychain

printf "\n\n👌 Awesome, all set.\n"

cat <<'EOF'

Next steps:

1. Steps to generate a PAT token
   - Go to GitHub > Settings > Developer settings > Personal access tokens.
   - Choose Tokens (classic).
   - Click Generate new token (classic), choose an expiration date, and grant the repository permissions you need.
   - Generate the token and copy it immediately. GitHub will only show it once.
   - Note: Use a fine-grained token instead when you want to limit access to specific repositories or your organization requires fine-grained PATs.

2. Add the PAT token to macOS Passwords app
   - Open the Passwords app on macOS.
   - Create a new password entry for github.com.
   - Use your GitHub username as the username.
   - Paste the PAT token into the password field and save it.
   - If Git prompts for credentials, use your GitHub username and the PAT token as the password. Git will save it in macOS Passwords/Keychain for future use.

EOF
