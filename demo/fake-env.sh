# Source this file in bash or zsh before running the demo.
# It clears common sensitive environment variables from the current shell
# and replaces them with obviously fake demo values.

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
unset AZURE_CLIENT_ID AZURE_CLIENT_SECRET AZURE_TENANT_ID
unset GOOGLE_API_KEY GOOGLE_APPLICATION_CREDENTIALS
unset OPENAI_API_KEY ANTHROPIC_API_KEY
unset GITHUB_TOKEN GH_TOKEN
unset DATABASE_URL STRIPE_API_KEY SENDGRID_API_KEY
unset NPM_TOKEN NETRC KUBECONFIG

export DEMO_HOST_ALIAS="demo-host"
export DEMO_USER_ALIAS="demo-user"
export DEMO_ACCOUNT_ID="acct-demo-1234"
export DEMO_REGION="us-demo-1"
export DEMO_REGISTRATION_TOKEN="reg_demo_abcd1234"

printf 'Loaded sanitized demo environment.\n'
printf '  DEMO_HOST_ALIAS=%s\n' "$DEMO_HOST_ALIAS"
printf '  DEMO_USER_ALIAS=%s\n' "$DEMO_USER_ALIAS"
printf '  DEMO_ACCOUNT_ID=%s\n' "$DEMO_ACCOUNT_ID"
printf '  DEMO_REGION=%s\n' "$DEMO_REGION"
