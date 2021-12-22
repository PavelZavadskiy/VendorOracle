// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "chainlink/contracts/src/v0.8/ChainlinkClient.sol";

//import "hardhat/console.sol";

interface I_ERC721{
    function balanceOf(address owner) external view returns (uint256);
}

interface I_LINK{
    function balanceOf(address owner) external view returns (uint256);
}

contract VendorOracle is Ownable, VRFConsumerBase, ChainlinkClient {
    using SafeERC20 for IERC20;
    using Chainlink for Chainlink.Request;

    address private token;
    address private agregatorEth;

    address _vrfCoordinator = 0xdD3782915140c8f3b190B5D67eAc6dc5760C46E9;
    address _linkToken = 0xa36085F69e2889c224210F603D836748e7dC0088;
    bytes32 _keyHash = 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4;

    address _oracle = 0xc57B33452b4F7BB189bB5AfaE9cc4aBa1f7a4FD8;
    bytes32 _jobId = "d5270d1c311941d0b08bead21fea7747";

    uint256 fee = 10**17;

    struct SForTransfer{
        address from;
        uint256 amount;
        uint256 randomMul;
        uint256 price;
        uint256 priceDecimals;
        bytes32 requestIdRandom;
        bytes32 requestIdPrice;
    }
    mapping (bytes32 => SForTransfer) private transationsRandom;
    mapping (bytes32 => SForTransfer) private transationsPrice;

    event BuyToken(address indexed _from, address indexed _to, uint256 _amount);

    constructor(address _token) VRFConsumerBase(_vrfCoordinator, _linkToken){
        token = _token;
        setPublicChainlinkToken();
    }

    function callBack(address _to, uint256 _amount, bytes memory _msg) private {
        bool sent;
        if(msg.value > 0){
            (sent, ) = payable(_to).call{value: _amount}(_msg);
        } else {
            (sent, ) = payable(_to).call(_msg);
        }
        require(sent, "Error calling the fallback function!");        
    }

    function buyToken() external payable{
        if(I_LINK(_linkToken).balanceOf(address(this)) < fee*2) {
            callBack(msg.sender, msg.value, "Not enough LINK - fill contract with faucet");
            //console.log("You can't buy token! You have not ERC721 token!");
            return;
        }
      
        Chainlink.Request memory request = buildChainlinkRequest(_jobId, address(this), this.fulfill.selector);
        
        // Set the URL to perform the GET request on
        request.add("get", "https://min-api.cryptocompare.com/data/pricemultifull?fsyms=ETH&tsyms=USD");
        request.add("path", "RAW.ETH.USD.VOLUME24HOUR");
        
        // Multiply the result by 1000000000000000000 to remove decimals
        int timesAmount = 10**18;
        request.addInt("times", timesAmount);

        bytes32 requestIdRandom = requestRandomness(_keyHash, fee);
        bytes32 requestIdPrice = sendChainlinkRequestTo(_oracle, request, fee);
        SForTransfer memory _transaction;
        _transaction.from = msg.sender;
        _transaction.amount = msg.value;
        _transaction.requestIdPrice = requestIdPrice;
        _transaction.requestIdRandom = requestIdRandom;
        transationsRandom[requestIdRandom] = _transaction;
        transationsPrice[requestIdPrice] = _transaction;
    } 

    function createTransaction(address sender, uint256 _amount, uint256 _price, uint256 _decimals, uint256 _randomMul) private
    {
        uint256 fullAmount = 0;
  
        fullAmount += (_amount * uint256(_price) * _randomMul) / (10**_decimals * 10);

        if(fullAmount == 0){
            callBack(payable(sender), _amount, "Your total amount of token is zerro!");
            //console.log("Your total amount of token is zerro!");
            return;
        }

        if(fullAmount > IERC20(token).balanceOf(address(this))){
            callBack(payable(sender), _amount, "Sorry, there is not enough tokens to buy!");
            //console.log("Sorry, there is not enough tokens to buy!");
            return;
        }

        IERC20(token).safeTransfer(sender, fullAmount);

        emit BuyToken(address(this), sender, fullAmount);
    }

    function fulfillRandomness(bytes32 _requestId, uint256 _randomness) internal override {
        SForTransfer storage _transactionRandom = transationsRandom[_requestId];
        SForTransfer storage _transactionPrice = transationsPrice[_transactionRandom.requestIdPrice];

        uint256 _randomMul = (_randomness % 26) + 5;

        _transactionRandom.randomMul = _randomMul;
        _transactionPrice.randomMul = _randomMul;
        
        if(_transactionRandom.price == 0) {
            return;
        }

        createTransaction(_transactionRandom.from, _transactionRandom.amount, _transactionRandom.price, _transactionRandom.priceDecimals, _transactionRandom.randomMul);
    
    }

    function fulfill(bytes32 _requestId, uint256 _volume) public recordChainlinkFulfillment(_requestId)
    {
        SForTransfer storage _transactionPrice = transationsPrice[_requestId];
        SForTransfer storage _transactionRandom = transationsRandom[_transactionPrice.requestIdRandom];

        uint256 _price = _volume;

        _transactionPrice.price = _price;
        _transactionPrice.priceDecimals = 18;

        _transactionRandom.price = _price;
        _transactionRandom.priceDecimals = 18;

        if(_transactionPrice.randomMul == 0) {
            return;
        }

        createTransaction(_transactionRandom.from, _transactionRandom.amount, _transactionRandom.price, _transactionRandom.priceDecimals, _transactionRandom.randomMul);
    }

    function claimAll() external onlyOwner {
        uint256 ethBalance = address(this).balance;
        if(ethBalance>0) {
            payable(owner()).transfer(ethBalance);
        }
    }
}