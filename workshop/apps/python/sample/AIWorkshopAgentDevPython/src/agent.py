import os
import sys
import json
import asyncio
import traceback
from http import HTTPStatus
from typing import Optional

import truststore
truststore.inject_into_ssl()

from dotenv import load_dotenv

from microsoft_agents.hosting.core import (
    AgentApplication,
    TurnState,
    TurnContext,
    MemoryStorage,
    Authorization,
)
from microsoft_agents.activity import (
    load_configuration_from_env,
    Activity,
    ActivityTypes,
)
from microsoft_agents.hosting.aiohttp import CloudAdapter
from microsoft_agents.authentication.msal import MsalConnectionManager

from azure.identity import ClientSecretCredential, DefaultAzureCredential
from azure.ai.projects import AIProjectClient

from config import Config
from graph import GraphService
from utils import extract_markdown_links, replace_markdown_links_with_order

load_dotenv()

# Load configuration
config = Config(os.environ)
agents_sdk_config = load_configuration_from_env(os.environ)


def get_credential():
    """Return the credential used to connect to the Microsoft Foundry project.

    Uses a user-assigned managed identity when running in Azure App Service,
    otherwise falls back to the SPN (client id/secret) for local development.
    """
    is_azure = bool(os.environ.get("WEBSITE_SITE_NAME"))

    if is_azure:
        print("Running in Azure. Using user assigned managed identity credential.")
        client_id = os.environ.get("ENV_AZURE_DEPLOY_USER_MANAGED_IDENTITY_CLIENT_ID")
        if not client_id:
            raise ValueError("ENV_AZURE_DEPLOY_USER_MANAGED_IDENTITY_CLIENT_ID is not set")
        return DefaultAzureCredential(managed_identity_client_id=client_id)

    print("Running locally. Using SPN identity credential.")
    return ClientSecretCredential(
        tenant_id=config.ENV_AZURE_APP_TENANT_ID,
        client_id=config.ENV_AZURE_APP_CLIENT_ID,
        client_secret=config.ENV_AZURE_APP_CLIENT_SECRET,
    )


# Authenticate against the Microsoft Foundry project
project_client = AIProjectClient(
    endpoint=config.ENV_AZURE_DEPLOY_AI_FOUNDRY_PROJECT_ENDPOINT,
    credential=get_credential(),
)

# Define storage and application
storage = MemoryStorage()
connection_manager = MsalConnectionManager(**agents_sdk_config)
adapter = CloudAdapter(connection_manager=connection_manager)
authorization = Authorization(storage, connection_manager, **agents_sdk_config)

agent_app = AgentApplication[TurnState](
    storage=storage,
    adapter=adapter,
    authorization=authorization,
    **agents_sdk_config,
)


def configure_agent_tools() -> None:
    """Register the SharePoint retrieval tool on the Foundry agent (once at startup)."""
    try:
        agent = project_client.agents.get(config.ENV_FOUNDRY_AGENT_NAME)

        sharepoint_tool = {
            "type": "function",
            "name": "getDocuments",
            "description": "Retrieve user documents from SharePoint based on the user query",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "The user optimized query as keywords",
                    }
                },
                "required": ["query"],
                "additional_properties": False,
            },
        }

        # Agents are immutable: read the latest definition and create a new version with the tool
        definition = agent.versions.latest.definition.as_dict()
        tools = definition.get("tools") or []
        tool_names = [tool.get("name") for tool in tools]

        if sharepoint_tool["name"] not in tool_names:
            tools.append(sharepoint_tool)
            definition["tools"] = tools
            project_client.agents.create_version(
                config.ENV_FOUNDRY_AGENT_NAME,
                definition=definition,
            )
            print(f"Successfully added SharePoint tool to agent '{config.ENV_FOUNDRY_AGENT_NAME}'")
        else:
            print("SharePoint tool already exists in the agent definition.")

    except Exception as e:
        print(f"Error configuring agent tools: {e}")
        raise


async def invoke_agent(context: TurnContext, access_token: str) -> None:
    """Forward the user message to the Foundry agent and process tool calls + citations."""
    try:
        client = project_client.get_openai_client()

        conversation = client.conversations.create(
            items=[
                {
                    "role": "user",
                    "content": context.activity.text,
                    "type": "message",
                }
            ],
            extra_body={"agent_reference": {"type": "agent_reference", "name": config.ENV_FOUNDRY_AGENT_NAME}},
        )

        response = client.responses.create(
            model=config.ENV_FOUNDRY_AGENT_MODEL,
            input=context.activity.text,
            conversation=conversation.id,
            extra_body={"agent_reference": {"type": "agent_reference", "name": config.ENV_FOUNDRY_AGENT_NAME}},
        )

        # Process the tool selection from the agent and execute the function ourselves
        graph_service = GraphService(access_token)
        input_list = []

        for item in response.output:
            item_type = getattr(item, "type", "")
            if item_type == "function_call" and item.name == "getDocuments":
                args = json.loads(item.arguments)
                documents = await graph_service.get_copilot_data(args.get("query", ""), context.activity.locale)
                formatted_docs = [
                    {
                        "title": doc.get("resourceMetadata", {}).get("title") or "No Title",
                        "url": doc.get("resourceMetadata", {}).get("url") or doc.get("webUrl") or "No URL",
                        "extracts": doc.get("extracts", []),
                    }
                    for doc in documents
                ]
                input_list.append(
                    {
                        "type": "function_call_output",
                        "call_id": item.call_id,
                        "output": json.dumps(formatted_docs),
                    }
                )

        # Provide the tool output back to the agent, reusing the previous response to keep context
        if input_list:
            response = client.responses.create(
                model=config.ENV_FOUNDRY_AGENT_MODEL,
                input=input_list,
                previous_response_id=response.id,
                extra_body={"agent_reference": {"type": "agent_reference", "name": config.ENV_FOUNDRY_AGENT_NAME}},
            )

        agent_answer = response.output[-1].content[0].text

        # Extract links from the answer and format them as proper citations
        links = extract_markdown_links(agent_answer)
        streaming_citations = [
            {
                "@type": "Claim",
                "position": i + 1,
                "appearance": {
                    "@type": "DigitalDocument",
                    "name": link["title"],
                    "url": link["url"],
                },
            }
            for i, link in enumerate(links)
        ]

        activity = Activity(
            type=ActivityTypes.message,
            text=replace_markdown_links_with_order(agent_answer),
            entities=[
                {
                    "type": "https://schema.org/Message",
                    "@type": "Message",
                    "@context": "https://schema.org",
                    "citation": streaming_citations,
                }
            ],
        )

        await context.send_activity(activity)

    except Exception as e:
        await context.send_activity(f"On message error. Details: {str(e)}")


async def invoke_agent_streaming(context: TurnContext) -> None:
    """Forward the user message to the Microsoft Foundry agent (streaming)."""
    try:
        context.streaming_response.set_generated_by_ai_label(True)
        await asyncio.sleep(0.1)

        context.streaming_response.set_feedback_loop(True)
        await asyncio.sleep(0.1)

        context.streaming_response.queue_informative_update("Working on your answer...")
        await asyncio.sleep(0.1)

        client = project_client.get_openai_client()

        conversation = client.conversations.create(
            items=[
                {
                    "role": "user",
                    "content": context.activity.text,
                    "type": "message",
                }
            ],
            extra_body={"agent_reference": {"type": "agent_reference", "name": config.ENV_FOUNDRY_AGENT_NAME}},
        )

        with client.responses.stream(
            model=config.ENV_FOUNDRY_AGENT_MODEL,
            input=context.activity.text,
            conversation=conversation.id,
            extra_body={"agent_reference": {"type": "agent_reference", "name": config.ENV_FOUNDRY_AGENT_NAME}},
        ) as stream:

            for event in stream:
                event_type = getattr(event, "type", "")
                if event_type == "response.output_text.delta":
                    delta = getattr(event, "delta", "")
                    if delta:
                        context.streaming_response.queue_text_chunk(delta)
                        await asyncio.sleep(0.05)

                elif event_type == "response.completed":
                    await context.streaming_response.end_stream()

    except Exception as e:
        await context.send_activity(f"On message error. Details: {str(e)}")


async def signin_success(context: TurnContext, state: TurnState, auth_id: Optional[str] = None) -> None:
    await context.send_activity(f"User signed in successfully in {auth_id}")


async def signin_failure(
    context: TurnContext, state: TurnState, auth_id: Optional[str] = None, err: Optional[str] = None
) -> None:
    await context.send_activity(f"Signing Failure in auth handler: {auth_id} with error: {err}")


agent_app.auth.on_sign_in_success(signin_success)
agent_app.auth.on_sign_in_failure(signin_failure)


@agent_app.message("/logout")
async def on_logout(context: TurnContext, state: TurnState):
    # This has to be registered before the general message handler
    await agent_app.auth.sign_out(context, "GRAPH")
    await context.send_activity("User logged out")


@agent_app.activity(ActivityTypes.message, auth_handlers=["GRAPH"])
async def on_message(context: TurnContext, state: TurnState):
    try:
        token_response = await agent_app.auth.get_token(context, "GRAPH")
        if token_response and token_response.token:
            await invoke_agent(context, token_response.token)
    except Exception as e:
        await context.send_activity(f"On message error. Details: {str(e)}")


@agent_app.activity(ActivityTypes.invoke)
async def on_invoke(context: TurnContext, state: TurnState):

    invoke_response = Activity(
        type=ActivityTypes.invoke_response,
        value={"status": HTTPStatus.OK},
    )

    if context.activity.name == "message/submitAction":
        action_value = context.activity.value
        action_name = action_value.get("actionName")

        if action_name == "feedback":
            feedback = action_value.get("actionValue", {}).get("feedback")
            await context.send_activity(f"Your feedback is {feedback}.")

        await context.send_activity(invoke_response)
    else:
        await context.send_activity(invoke_response)


@agent_app.error
async def on_error(context: TurnContext, error: Exception):
    # This check writes out errors to console log .vs. app insights.
    # NOTE: In production environment, you should consider logging this to Azure
    #       application insights.
    print(f"\n [on_turn_error] unhandled error: {error}", file=sys.stderr)
    traceback.print_exc()

    # Send a message to the user
    await context.send_activity("The agent encountered an error or bug.")
