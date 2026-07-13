# Source this file in bash or zsh before running the demo.
# It clears common sensitive environment variables from the current shell
# and sets the fake host/user aliases consumed by the payload.

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
unset AZURE_CLIENT_ID AZURE_CLIENT_SECRET AZURE_TENANT_ID
unset GOOGLE_API_KEY GOOGLE_APPLICATION_CREDENTIALS
unset OPENAI_API_KEY ANTHROPIC_API_KEY
unset GITHUB_TOKEN GH_TOKEN
unset DATABASE_URL STRIPE_API_KEY SENDGRID_API_KEY
unset NPM_TOKEN NETRC KUBECONFIG
unset SSH_AUTH_SOCK SSH_CONNECTION SSH_CLIENT SSH_TTY
unset CI_JOB_TOKEN CIRCLE_TOKEN CODECOV_TOKEN
unset DIGITALOCEAN_ACCESS_TOKEN CLOUDFLARE_API_TOKEN

export DEMO_HOST_ALIAS="demo-host"
export DEMO_USER_ALIAS="demo-user"

printf 'Loaded sanitized demo environment.\n'
printf '  DEMO_HOST_ALIAS=%s\n' "$DEMO_HOST_ALIAS"
printf '  DEMO_USER_ALIAS=%s\n' "$DEMO_USER_ALIAS"
printf 'Warning: this is best-effort sanitization, not an isolation boundary.\n'
printf 'It does not sanitize workspace files, Git config, credential stores, or unknown variables.\n'
