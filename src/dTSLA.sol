// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract dTSLA is ConfirmedOwner,FunctionsClient, ERC20 {
    using FunctionsRequest for FunctionsRequest.Request;
    using Strings for uint256;

    enum MintOrRedeem {
        mint,
        redeem
    }

    struct dTslaRequest{
        uint256 amountOfToken;
        address requester;
        MintOrRedeem mintOrRedeem;
    }

    error dTSLA__NotEnoughCollateral();
    error dTSLA__DoesntMeetMinimumCollateralAmount();
    error dTSLA__TransferFailed();

    uint256 constant PRECISION = 1e18;
    
    address constant SEPOLIA_FUNCTIONS_ROUTER = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    uint32 constant GAS_LIMIT = 300_000;
    bytes32 constant DON_ID = hex"66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000";
    address constant SEPOLIA_TSLA_PRICE_FEED = 0xc59E3633BAAC79493d908e63626716e204A45EdF; // LINK-USD For Demo 
    address constant SEPOLIA_USDC_PRICE_FEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E; // LINK-USD For Demo 
    address constant SEPOLIA_USDC = 0xAF0d217854155ea67D583E4CB5724f7caeC3Dc87;
    uint256 constant ADDITIONAL_FEE_PRECESION= 1e10;
    uint256 constant COLLATERAL_RATIO = 200;
    uint256 constant COLLATERAL_PRECISION = 100;
    uint256 constant MINIMUM_WITHDRAWAL_AMOUNT=100e18;
    uint8 donHostedSecretsSlotId=0;
    uint64 donHostedSecretsVersion=1712769962;

    uint64 immutable i_subId;

    string private s_mintSourceCode;
    string private s_redeemSourceCode;
    uint256 private s_portfolioBalance;

    mapping (bytes32 requestId => dTslaRequest request) private s_requestIdToRequest;
    mapping (address user => uint256 pendingWithdrawalAmount) private s_userToWithdrawalAmount;

    constructor(string memory mintSourceCode, uint64 subId, string memory redeemSourceCode) ConfirmedOwner(msg.sender) FunctionsClient(SEPOLIA_FUNCTIONS_ROUTER) ERC20("dTSLA", "dTSLA") {
        s_mintSourceCode = mintSourceCode;
        s_redeemSourceCode = redeemSourceCode;
        i_subId = subId;
    }

    
    function sendMintRequest(uint256 amount) external onlyOwner returns(bytes32) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(s_mintSourceCode);
        req.addDONHostedSecrets(donHostedSecretsSlotId, donHostedSecretsVersion);
        bytes32 requestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, DON_ID);
        s_requestIdToRequest[requestId] = dTslaRequest(amount, msg.sender, MintOrRedeem.mint);
        return requestId;

    }
    function _mintFulfillRequest(bytes32 requestId, bytes memory response) internal {
        uint256 amountOfTokensToMint = s_requestIdToRequest[requestId].amountOfToken;
        s_portfolioBalance = uint256(bytes32(response));
        if(_getCollateralRatioAdjustedTotalBalance(amountOfTokensToMint) > s_portfolioBalance){
            revert dTSLA__NotEnoughCollateral();
        }

        if(amountOfTokensToMint > 0){
            _mint(s_requestIdToRequest[requestId].requester, amountOfTokensToMint);
        }

    }

    function sendRedeemRequest(uint256 amountdTSLA) external {
        uint256 amountTslaInUsdc = getUsdcValueOfUsd(getUsdValueOfTsla(amountdTSLA));
        if(amountTslaInUsdc < MINIMUM_WITHDRAWAL_AMOUNT){
            revert dTSLA__DoesntMeetMinimumCollateralAmount();
        }
          FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(s_redeemSourceCode);

        string[] memory args = new string[](2);
        args[0]=amountdTSLA.toString();
        args[1]=amountTslaInUsdc.toString();
        req.setArgs(args);

        bytes32 requestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, DON_ID);
        s_requestIdToRequest[requestId] = dTslaRequest(amountdTSLA, msg.sender, MintOrRedeem.redeem);  

        _burn(msg.sender, amountdTSLA);
    }

    function getUsdcValueOfUsd(uint256 usdAmount) public view returns (uint256) {
        return (usdAmount * getUsdcPrice()) / PRECISION;
    }

    function getUsdValueOfTsla(uint256 tslaAmount) public view returns (uint256) {
        return (tslaAmount * getTslaPrice()) / PRECISION;
    }

    function _redeemFulfillRequest(bytes32 requestId, bytes memory response) internal {
        // assume this is 18 decimals
        uint256 usdcAmount = uint256(bytes32(response));
       if(usdcAmount ==0){
        uint256 amountOfdTslaBurned = s_requestIdToRequest[requestId].amountOfToken;
        _mint(s_requestIdToRequest[requestId].requester, amountOfdTslaBurned);
        return;
       }

       s_userToWithdrawalAmount[s_requestIdToRequest[requestId].requester] += usdcAmount;
    }

    function withdraw() external {
        uint256 amountToWithdraw = s_userToWithdrawalAmount[msg.sender];
        s_userToWithdrawalAmount[msg.sender] = 0;

        bool succ = ERC20(SEPOLIA_USDC).transfer(msg.sender, amountToWithdraw); 
        if(!succ){
            revert dTSLA__TransferFailed();
        }
    }


    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory /*err*/ ) internal override {
        dTslaRequest storage request = s_requestIdToRequest[requestId];
        if(request.mintOrRedeem == MintOrRedeem.mint){
            _mintFulfillRequest(requestId, response);
        }else{
            _redeemFulfillRequest(requestId, response);
        }
    }

    function _getCollateralRatioAdjustedTotalBalance(uint256 amountOfTokensToMint) internal view returns(uint256){
        uint256 calculatedNewTotalValue = getCalculatedNewTotalValue(amountOfTokensToMint);
        return (calculatedNewTotalValue * COLLATERAL_RATIO ) / COLLATERAL_PRECISION; 
    }

    function getCalculatedNewTotalValue(uint256 addedNumberOfTokens) internal view returns(uint256){
        return ((totalSupply() + addedNumberOfTokens) * getTslaPrice()) / PRECISION  ;
    }

    function getTslaPrice() public view  returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(SEPOLIA_TSLA_PRICE_FEED);
        (,int price,,,) = priceFeed.latestRoundData();
        return uint256(price)*ADDITIONAL_FEE_PRECESION; // 8 decimals * 10 decimals to get 18 deciamls
    }

    function getUsdcPrice() public view  returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(SEPOLIA_USDC_PRICE_FEED);
        (,int price,,,) = priceFeed.latestRoundData();
        return uint256(price)*ADDITIONAL_FEE_PRECESION; // 8 decimals * 10 decimals to get 18 deciamls
    }

    function getRequest(bytes32 requestId) public view returns (dTslaRequest memory) {
        return s_requestIdToRequest[requestId];
    }

    function getPortfolioBalance() public view returns (uint256) {
        return s_portfolioBalance;
    }

    function getPendingWithdrawalAmount(address user) public view returns (uint256) {
        return s_userToWithdrawalAmount[user];
    }

    function getSubId() public view returns (uint64) {
        return i_subId;
    }

    function getMintSourceCode() public view returns (string memory) {
        return s_mintSourceCode;
    }

    function getRedeemSourceCode() public view returns (string memory) {
        return s_redeemSourceCode;
    }

    
       
}