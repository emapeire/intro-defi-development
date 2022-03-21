//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Registry.sol";

contract Exchange is ERC20 {
    address public tokenAddress;
    address public registryAddress;

    constructor(address _token) ERC20("Exchange", "LP-EX") {
        require(_token != address(0), "Token address cannot be 0");
        tokenAddress = _token;
        registryAddress = msg.sender;
    }

    function addLiquidity(uint256 _tokenAmount) public payable returns (uint256) {
        uint256 mintedTokens;

        if (totalSupply() == 0) {
            mintedTokens = address(this).balance;
        } else {
            uint256 ethReserve = address(this).balance - msg.value;
            uint256 tokenReserve = getReserve();
            uint256 correctTokenAmount = (msg.value * tokenReserve) / ethReserve;
            require(_tokenAmount >= correctTokenAmount, "Not enough liquidity");
            mintedTokens = (totalSupply() * msg.value) / ethReserve;
        }

        IERC20 token = IERC20(tokenAddress);
        token.transferFrom(msg.sender, address(this), _tokenAmount);
        _mint(msg.sender, mintedTokens);
        return mintedTokens;
    }

    function removeLiquidity(uint256 _amount) public returns (uint256, uint256) {
        require(_amount > 0, "Amount must be greater than 0");
        uint256 ethAmount = (address(this).balance * _amount) / totalSupply();
        uint256 tokenAmount = (getReserve() * _amount) / totalSupply();

        _burn(msg.sender, _amount);

        payable(msg.sender).transfer(ethAmount);
        IERC20(tokenAddress).transfer(msg.sender, tokenAmount);

        return (ethAmount, tokenAmount);
    }

    function getReserve() public view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function getAmount(uint256 inputAmount, uint256 inputReserve, uint256 outputReserve) 
    private pure returns (uint256) {
        require(inputReserve > 0 && outputReserve > 0, "Input reserve must be greater than 0");
        
        /* uint256 outputAmount = (inputAmount * outputReserve) / 
        (inputReserve + inputAmount);
        return (outputAmount); */
        
        uint256 fee = 99;
        uint256 inputAmountWithFee = inputAmount * fee;
        uint256 numerator = inputAmountWithFee * outputReserve;
        uint256 denominator = (inputReserve * 100) + inputAmountWithFee;
        return numerator / denominator;
    }

    function getTokenAmount(uint256 _ethSold) public view returns (uint256) {
        require(_ethSold > 0, "Invalid Amount");
        uint256 tokenReserve = getReserve();
        return getAmount(_ethSold, address(this).balance, tokenReserve);
    }

    function getEthAmount(uint256 _tokenSold) public view returns (uint256) {
        require(_tokenSold > 0, "Invalid Amount");
        uint256 tokenReserve = getReserve();
        return getAmount(_tokenSold, tokenReserve, address(this).balance);
    }

    function ethToToken(uint256 _minTokens, address recipient) private {
        uint256 tokenReserve = getReserve();
        uint256 tokensBought = getAmount(msg.value, address(this).balance - msg.value, tokenReserve);
        require(tokensBought >= _minTokens, "Not enough tokens");
        IERC20(tokenAddress).transfer(recipient, tokensBought);
    }

    function ethToTokenSwap(uint256 _minTokens) public payable {
        ethToToken(_minTokens, msg.sender);
    }

    function ethToTokenTransfer(uint256 _minTokens, address _recipient) public payable {
        ethToToken(_minTokens, _recipient);
    }

    function tokenToEthSwap(uint256 _tokensSold, uint256 _minEth) public {
        uint256 tokenReserve = getReserve();
        uint256 ethBought = getAmount(_tokensSold, tokenReserve, address(this).balance);
        require(ethBought >= _minEth, "Not enough ETH");
        IERC20(tokenAddress).transferFrom(msg.sender, address(this), _tokensSold);
        payable(msg.sender).transfer(ethBought);
    }

    function tokenToTokenSwap(uint256 _tokensSold, uint256 _minTokenBought, address _tokenAddress)
    public {
        // this is SCAMM's Exchange
        // we want to buy DAI paying with SCAMM's tokens
        // ask the registry for the exchange address

        address exchangeAddress = Registry(registryAddress).getExchange(_tokenAddress);
        require(exchangeAddress != address(0), "Exchange does not exist");
        require(exchangeAddress != address(this), "Exchange does not exist");

        uint256 tokenReserve = getReserve();
        uint256 ethBought = getAmount(_tokensSold, tokenReserve, address(this).balance);

        IERC20(tokenAddress).transferFrom(msg.sender, address(this), _tokensSold);

        Exchange(exchangeAddress).ethToTokenTransfer{value: ethBought}
        (_minTokenBought, msg.sender);
    }
}