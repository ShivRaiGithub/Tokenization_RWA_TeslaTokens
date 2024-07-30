const requestConfig = require("../configs/alpacaMintConfig.js")
const {simulateScript, decodeResult} = require("@chainlink/functions-toolkit")

async function main(){
    const{responseByetsHexString, errorString, capturedTerminalOutput} =  await simulateScript(requestConfig);
    if(responseByetsHexString){
        console.log("Response: ", decodeResult(responseByetsHexString, requestConfig.expectedReturnType))
    }
    if(errorString){
        console.error("Error: ", errorString)
    }
}
main().catch((error)=>{
    console.error(error)
    process.exit(1)
})