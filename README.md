# Create a RAG-Powered AI Agent Using AI Foundry and Microsoft 365 Agents SDK

**Tags:** Microsoft Foundry · Microsoft 365 · RAG Pattern · ~5 hours

## Workshop Objective

This workshop provides a structured, step-by-step guide to building production-ready AI agents using the Retrieval-Augmented Generation (RAG) pattern. Participants will leverage Microsoft Foundry as the orchestration platform and integrate with Microsoft 365 through the Agents SDK. The content is designed around common enterprise constraints and real-world development practices.

## Modules

| Module | Description | Estimated Time |
|--------|-------------|----------------|
| [Module 1: Solution Overview, Architecture and Planning](./documentation/docs/modules/module1/index.mdx) | Introduces the Microsoft-based stack (M365, Azure, tooling), LLM selection criteria, and how to securely leverage Microsoft 365 knowledge sources. | 30 min |
| [Module 2: Provisioning Resources](./documentation/docs/modules/module2/index.mdx) | Automate infrastructure with Bicep, provision LLM resources, prepare data for RAG with SQL, AI Search embeddings, and chunking strategies. | 1 hr |
| [Module 3: Basic Agent Implementation in Microsoft Foundry](./documentation/docs/modules/module3/index.mdx) | Build a simple RAG agent in Node.js or Python with Azure AI Search integration. Design multi-agent workflows and evaluate responses in Foundry. | 30 min |
| [Module 4: Expose Your Agent to Teams and Copilot](./documentation/docs/modules/module4/index.mdx) | Implement the M365 Agents SDK with Foundry SDK, configure Azure Bot Service, debug locally with DevTunnels, and integrate with Copilot Studio. | 1 hr |
| [Module 5: Consuming Data from Microsoft 365 Copilot Retrieval API](./documentation/docs/modules/module5/index.mdx) | Enable SSO with Entra ID, integrate Microsoft Graph via LLM Tools and OpenAPI, and handle authentication flows in Teams and Copilot. | 1 hr |
| [Module 6: Deploy Your Agent to Azure and Microsoft 365](./documentation/docs/modules/module6/index.mdx) | Manage environments and solution lifecycle, deploy back-end services to Azure, and package and publish the Teams application. | 45 min |

## Prerequisites

- A dedicated Azure subscription with a Service Principal with Owner permissions
- Visual Studio Code with:
  - [Microsoft 365 Agents Toolkit](https://marketplace.visualstudio.com/items?itemName=TeamsDevApp.ms-teams-vscode-extension)
  - [SQL Server (mssql)](https://marketplace.visualstudio.com/items?itemName=ms-mssql.mssql)
  - [Python extension](https://marketplace.visualstudio.com/items?itemName=ms-python.python) (if using Python)
- **Node.js stack:** Node.js v22+ (recommend [nvm-windows](https://github.com/coreybutler/nvm-windows) or [nvm](https://github.com/nvm-sh/nvm))
- **Python stack:** Python 3.9+ from [python.org](https://www.python.org/downloads/)
- [PowerShell 7 (Core)](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows?view=powershell-7.5) with modules:
  ```powershell
  Install-Module -Name Az.Accounts, Az.Resources, Az.Network, Az.Websites, Az.KeyVault, SqlServer -Scope CurrentUser -Force -AcceptLicense
  ```
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/?view=azure-cli-latest)
- [Bicep v0.38.3+](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install#install-manually)
- [GitHub Copilot](https://github.com/features/copilot) (highly recommended, especially for Python developers)

## Getting Started

1. Clone the repository 
1. Run the documentation locally forn the `/documentation` folder:

```bash
npm i
npm run start
```

> You can also access the online documentation here: [https://app-docusaurops-build-it-ship-it-qlrnl.azurewebsites.net/build-it-ship-it](https://app-docusaurops-build-it-ship-it-qlrnl.azurewebsites.net/build-it-ship-it)