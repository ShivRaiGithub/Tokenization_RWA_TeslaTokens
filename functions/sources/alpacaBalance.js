if(
    secrets.alpacaKey == "" ||
    secrets.alpacaSecret == ""
){
    throw Error("Alpaca API Key and Secret are required");
}

const alpacaRequest = Functions.Http.makeRequest({
    url : "https://paper-api.alpaca.markets/v2/account",
    headers : {
        accept : "application/json",
        "APCA-API-KEY-ID" : secrets.alpacaKey,
        "APCA-API-SECRET-KEY" : secrets.alpacaSecret
    }
});

const [response] = await Promise.all({alpacaRequest});
const portfolioBalance = response.data.portfolio_value;
console.log("Alpaca portfolio balance: ", portfolioBalance);

return Functions.encodeUint256(Math.round(portfolioBalance * 100));
