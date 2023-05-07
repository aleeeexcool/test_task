// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract NFTWrapper is ERC721, ERC721Holder {
    using Counters for Counters.Counter;
    Counters.Counter public _tokenIds;

    address public owner;

    uint public protocolFee = 5;
    uint public constant FEE_DENOMINATOR = 1000;
    uint public usdcBalance;
    uint public feeAmount;

    IERC20 public usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IUniswapV2Router02 public uniswapRouter = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    
    struct amountForEachToken {
        address minter;
        uint amount;
        address tokenAddress;
    }

    mapping(address => bool) public allowedTokens;
    mapping(uint => amountForEachToken) public tokenIds;

    event TokensWrapped(address indexed tokenAddress, address indexed sender, uint amount, uint indexed tokenId);
    event TokensUnwrapped(address indexed tokenAddress, address indexed sender, uint amount, uint indexed tokenId);
    event TokenAdded(address indexed tokenAddress, address indexed sender);
    event TokenRemoved(address indexed tokenAddress, address indexed sender);
    event ProtocolFeeChanged(uint fee);

    constructor() ERC721("MyNFT", "MNFT") {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    function wrapTokens(address _tokenAddress, uint _amount) public {
        require(allowedTokens[_tokenAddress], "Token not allowed");
        require(_amount > 0, "Amount must be greater than zero");

        IERC20 token = IERC20(_tokenAddress);
        // token.approve(address(this), _amount);
        token.transferFrom(tx.origin, address(this), _amount);

        uint newId = _tokenIds.current();
        _tokenIds.increment();
        _safeMint(tx.origin, newId);

        tokenIds[newId] = amountForEachToken(tx.origin, _amount, _tokenAddress);

        emit TokensWrapped(_tokenAddress, tx.origin, _amount, newId);
    }

    function unwrapTokens(address _tokenAddress, uint _tokenId) public {
        require(ownerOf(_tokenId) == msg.sender, "Sender does not own this NFT");
        require(allowedTokens[_tokenAddress], "Token not allowed");
        require(tokenIds[_tokenId].tokenAddress == _tokenAddress, "Invalid token address");

        uint amount_ = getWrappedTokenAmount(_tokenId);
        _burn(_tokenId);
        delete tokenIds[_tokenId];
        uint amountWithoutFee = amount_ * protocolFee / FEE_DENOMINATOR;
        feeAmount += amountWithoutFee;

        IERC20 token = IERC20(_tokenAddress);
        token.transfer(tx.origin, amountWithoutFee);

        emit TokensUnwrapped(_tokenAddress, tx.origin, amountWithoutFee, _tokenId);
    }

    function getWrappedTokenAmount(uint _tokenId) public view returns (uint) {
        require(ownerOf(_tokenId) != address(0), "Invalid NFT");

        uint amount = tokenIds[_tokenId].amount;
        return amount;
    }

    function addToken(address _tokenAddress) public onlyOwner {
        require(!allowedTokens[_tokenAddress], "Token already allowed");

        allowedTokens[_tokenAddress] = true;
        emit TokenAdded(_tokenAddress, msg.sender);
    }

    function removeToken(address _tokenAddress) public onlyOwner {
        require(allowedTokens[_tokenAddress], "Token not allowed");

        allowedTokens[_tokenAddress] = false;
        emit TokenRemoved(_tokenAddress, msg.sender);
    }

    function setProtocolFee(uint _protocolFee) public onlyOwner {
        require(_protocolFee <= FEE_DENOMINATOR, "Fee can't be higher than 100%");
        protocolFee = _protocolFee;

        emit ProtocolFeeChanged(_protocolFee);
    }

    function withdrawFees() public onlyOwner {
        usdc.approve(address(uniswapRouter), feeAmount);

        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = uniswapRouter.WETH();

        IUniswapV2Router02(uniswapRouter).swapExactTokensForETH(
            feeAmount,
            0,
            path,
            msg.sender,
            block.timestamp
        );

        usdcBalance -= feeAmount;
    }

    function deposit() public payable {
        require(msg.sender == address(usdc), "Invalid sender");
        usdcBalance += msg.value;
    }
}
