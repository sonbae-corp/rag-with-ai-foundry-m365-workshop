import { startServer } from "@microsoft/agents-hosting-express";
import { CustomAgent } from "./agent";
import { MemoryStorage, TurnContext } from "@microsoft/agents-hosting";

const onTurnErrorHandler = async (context: TurnContext, error: Error) => {

  console.error(`\n [onTurnError] unhandled error: ${error}`);

  await context.sendTraceActivity(
    "OnTurnError Trace",
    `${error}`,
    "https://www.botframework.com/schemas/error",
    "TurnError"
  );

  await context.sendActivity(
    `The bot encountered unhandled error:\n ${error.message}`
  );
  await context.sendActivity(
    "To continue to run this bot, please fix the bot source code."
  );
};

const storage = new MemoryStorage();
const customAgent = new CustomAgent(storage);
customAgent.adapter.onTurnError = onTurnErrorHandler;

startServer(customAgent);