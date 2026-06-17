const config = {
    aiFoundryProjectEndpoint: process.env.ENV_AZURE_DEPLOY_AI_FOUNDRY_PROJECT_ENDPOINT,
    tenantId: process.env.ENV_AZURE_APP_TENANT_ID,
    clientId: process.env.ENV_AZURE_APP_CLIENT_ID,
    clientSecret: process.env.ENV_AZURE_APP_CLIENT_SECRET,
    agentName: process.env.ENV_FOUNDRY_AGENT_NAME
};

export default config;