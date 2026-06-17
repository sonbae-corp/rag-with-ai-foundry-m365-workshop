import httpx
from typing import Optional, List, Any


class GraphService:

    def __init__(self, access_token: str):
        self.access_token = access_token

    async def get_copilot_data(self, query: str, language: Optional[str] = None) -> List[Any]:

        request_body = {
            "queryString": query,
            "dataSource": "sharePoint",
            "resourceMetadata": ["title", "url"],
            "maximumNumberOfResults": 5,
        }

        headers = {
            "Authorization": f"Bearer {self.access_token}",
            "Content-Type": "application/json",
            "SdkVersion": "ContosoEnterpriseSearchAgent",
            "Accept-Language": language if language else "en-US",
        }

        url = "https://graph.microsoft.com/v1.0/copilot/retrieval"

        async with httpx.AsyncClient() as client:
            response = await client.post(url, json=request_body, headers=headers)

            if response.status_code == 200:
                data = response.json()
                return data.get("retrievalHits", [])

            print(f"Error: {response.status_code} - {response.text}")
            return []
