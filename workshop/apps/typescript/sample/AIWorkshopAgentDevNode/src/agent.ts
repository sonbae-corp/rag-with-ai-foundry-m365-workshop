import { AgentApplication, MessageFactory, StatusCodes, Storage, TurnContext, TurnState } from "@microsoft/agents-hosting";
import { ClientSecretCredential, DefaultAzureCredential, TokenCredential } from "@azure/identity";
import { Activity, ActivityTypes } from "@microsoft/agents-activity";
import { AIProjectClient } from "@azure/ai-projects";
import config from "./config";
import { GraphService } from "./graph";
import { Utils } from "./utils";

export class CustomAgent extends AgentApplication<TurnState> {

    constructor (storage: Storage) {
        super({
            storage: storage,
            authorization: {
                graph: { 
                text: 'Sign in with Microsoft Graph', 
                title: 'Sign In'
                },
            }
        });

        this._onMessage = this._onMessage.bind(this);
        this._singinSuccess = this._singinSuccess.bind(this);
        this._singinFailure = this._singinFailure.bind(this);

        this.authorization.onSignInSuccess(this._singinSuccess);
        this.authorization.onSignInFailure(this._singinFailure);

        this.configureAgentTools().then(() => {
            console.log("Agent tools configured.");
        });

        this.onActivity(ActivityTypes.Message, this._onMessage, ['graph']);
        this.onActivity(ActivityTypes.Invoke, this._onInvoke);
    }

    // private async _onMessage(context: TurnContext, state: TurnState) {   

    //     // Non streaming mode
    //     //await this.invokeAgent(context);

    //     await this.invokeAgentWithStreaming(context);
    // }

    private async configureAgentTools() {

        const foundryProject = new AIProjectClient(config.aiFoundryProjectEndpoint!, this.getCredential());
        const agent = await foundryProject.agents.get(config.agentName as string);

        const sharePointTool = {
            type: "function",
            name: "getDocuments",
            description: "Retrieve user documents from SharePoint based on the user query",
            parameters: {
            type: "object",
            properties: {
                query: { type: "string", description: "The user optimized query as keywords" },
            },
            required: ["query"],
            additional_properties: false
            }
        }
        
        const { tools } = agent.versions.latest.definition as any;
        if (tools.map((t: { name: any; }) => t.name).indexOf(sharePointTool.name) === -1) {

            try {     
                (agent.versions.latest.definition as any).tools.push(sharePointTool);
                await foundryProject.agents.update(config.agentName as string, {...agent.versions.latest.definition});
            } catch (error) {
                throw new Error(`Failed to update agent tools: ${error}`);
            }
            
        } else {
            console.log("SharePoint tool already exists in the agent definition.");
        }
    }

    private async _onMessage(context: TurnContext, state: TurnState) {

        try {

            let userTokenResponse;
            userTokenResponse = await this.authorization.getToken(context, 'graph');
            if (userTokenResponse && userTokenResponse?.token) {   
                await this.invokeAgent(context, userTokenResponse.token);
            }

        } catch (ex) {
        await context.sendActivity(`On message error. Details: ${JSON.stringify(ex)}`);       
        }
    }

    private async _singinSuccess(context: TurnContext, state: TurnState, authId?: string): Promise<void> {
        await context.sendActivity(MessageFactory.text(`User signed in successfully in ${authId}`))
    }

    private async _singinFailure (context: TurnContext, state: TurnState, authId?: string, err?: string): Promise<void> {
        await context.sendActivity(MessageFactory.text(`Signing Failure in auth handler: ${authId} with error: ${err}`))
    }

    private async invokeAgent(context: TurnContext, accessToken: string) {

        const foundryProject = new AIProjectClient(config.aiFoundryProjectEndpoint!, this.getCredential());

        const items: any[] = [{
            type: "message",
            role: "user",
            content: context.activity.text
        }];

        const client = await foundryProject.getOpenAIClient();
        const conversation = await client.conversations.create({
            items,
            agent_reference:{ 
                type: "agent_reference",
                name: config.agentName 
            } 

        } as any);

        let response = await client.responses.create(
            {
                input: context.activity.text,
                conversation: conversation.id,
                agent_reference:{ 
                    type: "agent_reference",
                    name: config.agentName 
                }
            }  as any
        );

        // const lastOutput = response.output[response.output.length - 1] as { content?: Array<{ text?: string }> };
        // await context.sendActivity(lastOutput.content?.[0]?.text ?? "");

        const graphService = new GraphService(accessToken);
        const inputList =[];

        for (const item of response.output) {

            if (item.type === "function_call") {

                switch (item.name) {
                    case "getDocuments":
                        // Parse the function arguments
                        const args = JSON.parse(item.arguments);

                        // Execute the function logic
                        const documents = await graphService.getCopilotData(args.query, context.activity.locale);

                        // Reformat the output for the LLM
                        const formattedDocs = documents.map((doc: any) => {
                            return {
                                title: doc.resourceMetadata?.title || "No Title",
                                url: doc.resourceMetadata?.url || doc.webUrl || "No URL",
                                extracts: doc.extracts || []
                            };
                        });

                        // Provide function call results to the model
                        inputList.push({
                            type: "function_call_output",
                            call_id: item.call_id,
                            output: JSON.stringify({ formattedDocs }),
                        });

                    break;
                        default:
                        console.warn(`Unknown function call: ${item.name}`);
                    break;
                }
            }
        }

        // Build previous response including tool output
        response = await client.responses.create(
            {
                input: inputList,
                previous_response_id: response.id,
                agent_reference:{ 
                    type: "agent_reference",
                    name: config.agentName 
                }
            } as any
        );

        const lastOutput = response.output[response.output.length - 1] as { content?: Array<{ text?: string }> };

        const agentAnswer: string = lastOutput.content?.[0]?.text ?? ""

        // Extract links from the answer for citations
        const links = Utils.extractMarkdownLinks(agentAnswer);

        const streamingCitations = links.map((link, i) => {

            return {
            "@type": "Claim",
            position: ++i,
            appearance: {
                "@type": "DigitalDocument",
                name: link.title,
                url: link.url
            },
            };
        });

        const activity = Activity.fromObject({
            type: ActivityTypes.Message,
            text: Utils.replaceMarkdownLinksWithOrder(agentAnswer),
            entities: [
            {
            type: "https://schema.org/Message",
            "@type": "Message",
            "@context": "https://schema.org",
            citation: streamingCitations,
            }]
        });

        await context.sendActivity(activity);
    }

    private async invokeAgentWithStreaming(context: TurnContext) {

        // Configure streaming response
        await context.streamingResponse.setDelayInMs(100);
        await context.streamingResponse.setGeneratedByAILabel(true);
        await context.streamingResponse.setFeedbackLoop(true);
        await context.streamingResponse.queueInformativeUpdate('Working on your answer...');

        const foundryProject = new AIProjectClient(config.aiFoundryProjectEndpoint!, this.getCredential());

        const items: any[] = [{
            type: "message",
            role: "user",
            content: context.activity.text
        }];

        const client = await foundryProject.getOpenAIClient();
        const conversation = await client.conversations.create({
            items,
            agent_reference:{ 
                type: "agent_reference",
                name: config.agentName 
            } 

        } as any);

        // Streaming mode: process events and send to Teams
        const responseStream = client.responses.stream(
        {
                input: context.activity.text,
                conversation: conversation.id,
                agent_reference:{ 
                    type: "agent_reference",
                    name: config.agentName 
                }
            }  as any
        );

        for await (const event of responseStream) {

            if (event.type === "response.output_text.delta") {
                if (event.delta && context) {
                    await context.streamingResponse.queueTextChunk(event.delta);
                }
            } 
            else if (event.type === "response.output_text.done") {
                
                if (event.text && context) {
                await context.streamingResponse.queueTextChunk(event.text);
                }

            } 
            else if (event.type === "response.completed") {
                await context.streamingResponse.endStream();
            }
        }
    }

    private async _onInvoke(context: TurnContext): Promise<any> {

        const invokeResponse = Activity.fromObject({ type: ActivityTypes.InvokeResponse, value: { status: StatusCodes.OK}});

        switch (context.activity.name) {
            case "message/submitAction":

                const { actionName, actionValue } = context.activity.value as any;
                if (actionName === "feedback") {
                    await context.sendActivity(`Your feedback is ${actionValue.feedback}.`);
                }
                await context.sendActivity(invokeResponse);
                
            default:      
                await context.sendActivity(invokeResponse);
        }
    };

    public getCredential(): TokenCredential {

        const isAzure = !!process.env["WEBSITE_SITE_NAME"];

        if (isAzure) {
            console.log("Running in Azure. Using user assigned managed identity credential.");

            const clientId = process.env["ENV_AZURE_DEPLOY_USER_MANAGED_IDENTITY_CLIENT_ID"];
            if (!clientId) {
                throw new Error("ENV_AZURE_DEPLOY_USER_MANAGED_IDENTITY_CLIENT_ID is not set");
            }

            return new DefaultAzureCredential({ managedIdentityClientId: clientId });
        }

        console.log("Running locally. Using SPN identity credential.");

        return new ClientSecretCredential(
            config.tenantId!,
            config.clientId!,
            config.clientSecret!
        );
    }
}