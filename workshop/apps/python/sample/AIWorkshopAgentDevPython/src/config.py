"""
Copyright (c) Microsoft Corporation. All rights reserved.
Licensed under the MIT License.
"""

import os

class Config:
    """Agent Configuration"""

    def __init__(self, env):
        self.PORT = 3978
        self.azure_openai_api_key = env["AZURE_OPENAI_API_KEY"] # Azure OpenAI API key
        self.azure_openai_deployment_name = env["AZURE_OPENAI_DEPLOYMENT_NAME"] # Azure OpenAI model deployment name
        self.azure_openai_endpoint = env["AZURE_OPENAI_ENDPOINT"] # Azure OpenAI endpoint

        self.ENV_AZURE_DEPLOY_AI_FOUNDRY_PROJECT_ENDPOINT = env.get(
            "ENV_AZURE_DEPLOY_AI_FOUNDRY_PROJECT_ENDPOINT",
            os.getenv("ENV_AZURE_DEPLOY_AI_FOUNDRY_PROJECT_ENDPOINT"),
        )
        self.ENV_AZURE_APP_TENANT_ID = env.get(
            "ENV_AZURE_APP_TENANT_ID", os.getenv("ENV_AZURE_APP_TENANT_ID")
        )
        self.ENV_AZURE_APP_CLIENT_ID = env.get(
            "ENV_AZURE_APP_CLIENT_ID", os.getenv("ENV_AZURE_APP_CLIENT_ID")
        )
        self.ENV_AZURE_APP_CLIENT_SECRET = env.get(
            "ENV_AZURE_APP_CLIENT_SECRET", os.getenv("ENV_AZURE_APP_CLIENT_SECRET")
        )
        self.ENV_FOUNDRY_AGENT_NAME = env.get(
            "ENV_FOUNDRY_AGENT_NAME", os.getenv("ENV_FOUNDRY_AGENT_NAME")
        )
        self.ENV_FOUNDRY_AGENT_MODEL = env.get(
            "ENV_FOUNDRY_AGENT_MODEL",
            os.getenv("ENV_FOUNDRY_AGENT_MODEL", "gpt-4.1-nano"),
        )
