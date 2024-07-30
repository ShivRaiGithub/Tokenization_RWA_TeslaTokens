const{
    SecretsManager
} = require("@chainlink/functions-toolkit");
const ethers = require("ethers");


async function uploadSecrets(){
    const routerAddress="0xb83E47C2bC239B3bf370bc41e1459A34b41238D0";
    const donId = "fun-ethereum-sepolia-1";
    const gatewayUrls = ["https://02.functions-gateway.testnet.chain.link/", "https://01.functions-gateway.testnet.chain.link/"];

    const privateKey =  process.env.PRIVATE_KEY;
    const rpcUrl = process.env.SEPOLIA_RPC_URL;
    const secrets = {alpacaKey: process.env.ALPACA_KEY, alpacaSecret: process.env.ALPACA_SECRET}

    const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey);
    const signer = wallet.connect(provider);

    const secretsManager = new SecretsManager(signer, routerAddress, donId);
    await secretsManager.initialize();

    const encryptedSecrets = await secretsManager.encryptSecrets(secrets);
    const slotIdNumber = 0;
    const expirationTineMinutes=1440;
    const uploadResult = await secretsManager.uploadEncryptedSecretsToDON({
        encryptedSecretsHexstring: encryptedSecrets.encryptedSecrets,
        gatewayUrls: gatewayUrls,
        slotId: slotIdNumber,
        minutesUntilExpiration: expirationTineMinutes

    })

    if(!uploadResult.success){
        throw new Error("Failed to upload secrets to DON", uploadResult.errorMessage)
    }

    console.log("Secrets uploaded successfully", uploadResult);
    const donHostedSecretsVersion = parseInt(uploadResult.version);
    console.log("Secrets version", donHostedSecretsVersion);

}

uploadSecrets().catch((error)=>{
    console.error(error)
    process.exit(1)
})