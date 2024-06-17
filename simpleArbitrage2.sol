// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface KyberNetwork {
    function trade(
        IERC20 src,
        uint srcAmount,
        IERC20 dest,
        address destAddress,
        uint maxDestAmount,
        uint minConversionRate,
        address walletId
    ) external payable returns(uint);

    function getExpectedRate(
        IERC20 src,
        IERC20 dest,
        uint srcQty
    ) external view returns (uint expectedRate, uint slippageRate);
}

interface Uniswap {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

contract ArbitrajeEth is Ownable {
    KyberNetwork kyber;
    Uniswap uniswap;
    IERC20 constant dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI token address
    address payable public owner;

    constructor(address _kyber, address _uniswap) {
        kyber = KyberNetwork(_kyber);
        uniswap = Uniswap(_uniswap);
        owner = payable(msg.sender);
    }

    receive() external payable {
        // Accept ETH sent to this contract
    }

    function startArbitrage(uint amountIn) external onlyOwner {
        // Perform arbitrage between Kyber and Uniswap
        // Assume WETH (ETH wrapped as ERC20) is used as the trading pair

        // Step 1: Trade on Kyber (Buy WETH with DAI)
        uint minConversionRate;
        (, minConversionRate) = kyber.getExpectedRate(dai, IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), amountIn);
        uint ethBought = kyber.trade(
            IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F), // DAI
            amountIn,
            IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // WETH
            address(this),
            type(uint).max,
            minConversionRate,
            0
        );

        // Step 2: Trade on Uniswap (Sell WETH for DAI)
        address[] memory path = new address[](2);
        path[0] = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH
        path[1] = address(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI

        uint[] memory amounts = uniswap.swapExactTokensForTokens(
            ethBought,
            0,
            path,
            address(this),
            block.timestamp + 1800 // 30 minutes deadline from now
        );

        // Arbitrage completed, profit is the difference between amounts[1] and amountIn
        uint profit = amounts[1] - amountIn;

        // Transfer profit in Ether to contract owner
        owner.transfer(profit);
    }

    function withdrawTokens(address token, uint amount) external onlyOwner {
        IERC20(token).transfer(owner, amount);
    }

    function withdrawEther() external onlyOwner {
        owner.transfer(address(this).balance);
    }

    function setOwner(address payable _owner) external onlyOwner {
        owner = _owner;
    }

    // Fallback function to reject Ether sent to this contract
    fallback() external payable {
        revert();
    }
}
