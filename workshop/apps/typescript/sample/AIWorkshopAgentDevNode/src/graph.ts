import { Client } from "@microsoft/microsoft-graph-client";

export class GraphService {

    private graphClient: Client;

    constructor(accessToken: string) {

        this.getCopilotData = this.getCopilotData.bind(this);
        this.graphClient =  Client.initWithMiddleware(
            {
                authProvider: {
                    getAccessToken: async () => {
                        return accessToken
                    },
                }
            } 
        );
    }      

    public async getCopilotData(query: string, language?: string): Promise<any[]> {
    
        const response = await this.graphClient.api("/copilot/retrieval").headers({ 
              "SdkVersion": "ContosoEnterpriseSearchAgent",  
              "Accept-language": language ? language : "en-US"
            }).post({
            queryString: query,
            dataSource: "sharePoint",
            resourceMetadata: ['title','url'],
            maximumNumberOfResults: 5
        });

        return response.retrievalHits;
    }
}