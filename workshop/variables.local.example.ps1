#region WORKSHOP VARIABLES

  # What you need to update
  $ENV_WEBAPP_STACK="python" # Options: "node" | "python"
  $ENV_DEVELOPER_NAME="<your_name>"
  $ENV_AZURE_DEPLOY_TENANT_ID="<your-tenant-id>"
  $ENV_AZURE_DEPLOY_APP_CLIENT_ID="<your-deploy-app-client-id>"
  $ENV_AZURE_DEPLOY_APP_CLIENT_SECRET="<your-client-secret-from-secure-store>" 
  $ENV_AZURE_DEPLOY_SUBSCRIPTION_ID="<your-subscription-id>"
  $ENV_AZURE_DEPLOYMENT_STACK_SQL_ADMINS_ENTRA_GROUP_NAME = "Workshop SQL Admins"
  $ENV_AZURE_DEPLOYMENT_STACK_SQL_ADMINS_ENTRA_GROUP_ID = "<your-sql-admins-entra-group-id>"
  $ENV_SQL_SERVER_NAME =  "sql-ai-<id>.database.windows.net"
  $ENV_SQL_DATABASE_NAME = "sqldb-ai-<id>"
  $ENV_AZURE_SEARCH_APP_OAUTH_CONNECTION_CLIENT_ID="<your-oauth-client-id>"
  $ENV_AZURE_SEARCH_APP_OAUTH_CONNECTION_CLIENT_SECRET="<your-client-secret-from-secure-store>"

  # Variables below are default for the workshop
  $ENV_AZURE_LOCATION="westus"
  $ENV_AZURE_ENV_STAGE="$ENV_DEVELOPER_NAME-workshop-$ENV_AZURE_LOCATION"
  $ENV_AZURE_DEPLOYMENT_STACK_ENV_NAME = "ai-knowledge-agent-$ENV_AZURE_ENV_STAGE"
  $ENV_FOUNDRY_AGENT_NAME="ai-knowledge-agent"
  $ENV_AZURE_DEPLOYMENT_STACK_RG_NAME="rg-$ENV_AZURE_DEPLOYMENT_STACK_ENV_NAME"
  $ENV_MODULES_CONFIG = @{ 
    "Module1" = @{
      Resources = @(
        'SQLServer'
      );
      Capabilities = @()
    };
    "Module2.1" = @{
      Resources = @(
        'SQLServer'
        'AIFoundry'
      );
      Capabilities = @(
        'AIFoundry/EmbeddingModel'
      )
    };
    "Module2.2" = @{
      Resources = @(
        'SQLServer'
        'AIFoundry',
        'AISearch'
      );
      Capabilities = @(
        'AIFoundry/EmbeddingModel'
      )
    };
    "Module3.1" = @{
      Resources = @(
        'SQLServer'
        'AIFoundry',
        'AISearch'
      );
      Capabilities = @(
        'AIFoundry/EmbeddingModel',
        'AIFoundry/CompletionModel',
        'AIFoundry/AISearchConnection'
      )
    };
    "Module6"= @{
      Resources = @(
        'SQLServer'
        'AIFoundry',
        'AISearch',
        'AppService',
        'BotService',
        'KeyVault'
      );
      Capabilities = @(
        'AIFoundry/EmbeddingModel',
        'AIFoundry/CompletionModel',
        'AIFoundry/AISearchConnection'
      )
    };
  }
  $ENV_AZURE_SEARCH_APP_OAUTH_CONNECTION_NAME="copilotCustomAuth"
  $ENV_SQL_DATA_TABLE_NAME =  "Articles"
  $ENV_SQL_DATA_TABLE_SCHEMA = "dbo"

#endregion