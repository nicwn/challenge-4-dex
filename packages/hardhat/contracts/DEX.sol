// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DEX Template
 * @author stevepham.eth and m00npapi.eth
 * @notice Empty DEX.sol that just outlines what features could be part of the challenge (up to you!)
 * @dev We want to create an automatic market where our contract will hold reserves of both ETH and 🎈 Balloons. These reserves will provide liquidity that allows anyone to swap between the assets.
 * NOTE: functions outlined here are what work with the front end of this challenge. Also return variable names need to be specified exactly may be referenced (It may be helpful to cross reference with front-end code function calls).
 */
contract DEX {
	/* ========== GLOBAL VARIABLES ========== */

	IERC20 token; //instantiates the imported contract
	uint256 public totalLiquidity; // tracks the total liquidity in the exchange
	mapping(address => uint256) public liquidity; // tracks individual liquidity contributions. Liquidity is a proportional share of the pool.

	/* ========== EVENTS ========== */

	/**
	 * @notice Emitted when ethToToken() swap transacted
	 */
	event EthToTokenSwap(
		address swapper,
		uint256 tokenOutput,
		uint256 ethInput
	);

	/**
	 * @notice Emitted when tokenToEth() swap transacted
	 */
	event TokenToEthSwap(
		address swapper,
		uint256 tokensInput,
		uint256 ethOutput
	);

	/**
	 * @notice Emitted when liquidity provided to DEX and mints LPTs.
	 */
	event LiquidityProvided(
		address liquidityProvider,
		uint256 liquidityMinted,
		uint256 ethInput,
		uint256 tokensInput
	);

	/**
	 * @notice Emitted when liquidity removed from DEX and decreases LPT count within DEX.
	 */
	event LiquidityRemoved(
		address liquidityRemover,
		uint256 liquidityWithdrawn,
		uint256 tokensOutput,
		uint256 ethOutput
	);

	/* ========== CONSTRUCTOR ========== */

	constructor(address tokenAddr) {
		token = IERC20(tokenAddr); //specifies the token address that will hook into the interface and be used through the variable 'token'
	}

	/* ========== MUTATIVE FUNCTIONS ========== */

	/**
	 * @notice initializes amount of tokens that will be transferred to the DEX itself from the erc20 contract mintee (and only them based on how Balloons.sol is written). Loads contract up with both ETH and Balloons.
	 * @param tokens amount to be transferred to DEX
	 * @return totalLiquidity is the number of LPTs minting as a result of deposits made to DEX contract
	 * NOTE: since ratio is 1:1, this is fine to initialize the totalLiquidity (wrt to balloons) as equal to eth balance of contract.
	 */
	function init(uint256 tokens) public payable returns (uint256) {
		// Check if liquidity already exists, ensures the DEX can only be initialized once
		require(totalLiquidity == 0, "DEX: init - already has liquidity");

		// Set the totalLiquidity to the contract's ETH balance
		totalLiquidity = address(this).balance;

		// Assign all liquidity to the initializer. Important for tracking who can withdraw liquidity later.
		liquidity[msg.sender] = totalLiquidity;

		// Transfer tokens from sender to this contract and verify the transfer
		// Note that we're using the token variable which was defined in the constructor
		require(token.transferFrom(msg.sender, address(this), tokens), "DEX: init - transfer did not transact");

		return totalLiquidity;
	}

	/**
	 * @notice returns yOutput, or yDelta for xInput (or xDelta)
	 * @dev Follow along with the [original tutorial](https://medium.com/@austin_48503/%EF%B8%8F-minimum-viable-exchange-d84f30bd0c90) Price section for an understanding of the DEX's pricing model and for a price function to add to your contract. You may need to update the Solidity syntax (e.g. use + instead of .add, * instead of .mul, etc). Deploy when you are done. See: https://youtu.be/IL7cRj5vzEU
	 */
	function price(
		uint256 xInput,
		uint256 xReserves,
		uint256 yReserves
	) public pure returns (uint256 yOutput) {
		// Apply the fee to xInput (0.3% fee means 99.7% of input is used)
    	uint256 xInputWithFee = xInput * 997;
    
    	// Calculate output based on constant product formula: dy = y * 0.997 * dx / (x + 0.997 * dx)
    	uint256 numerator = xInputWithFee * yReserves;
    	uint256 denominator = (xReserves * 1000) + xInputWithFee;
		// This is the same as: dy = (yReserves * xInput * 997) / (xReserves * 1000 + 997 * xInput)
    	return numerator / denominator;
	}


	/**
	 * @notice returns liquidity for a user.
	 * NOTE: this is not needed typically due to the `liquidity()` mapping variable being public and having a getter as a result. This is left though as it is used within the front end code (App.jsx).
	 * NOTE: if you are using a mapping liquidity, then you can use `return liquidity[lp]` to get the liquidity for a user.
	 * NOTE: if you will be submitting the challenge make sure to implement this function as it is used in the tests.
	 */
	function getLiquidity(address lp) public view returns (uint256) {
		return liquidity[lp];
	}

	/**
	 * @notice sends Ether to DEX in exchange for $BAL
	 */
	function ethToToken() public payable returns (uint256 tokenOutput) {
		// Make sure the value being swapped for balloons is greater than 0
		require(msg.value > 0, "cannot swap 0 ETH");
		//  When we call this function, it will already have the value we sent it in it's liquidity. Make sure we are using the balance of the contract before any ETH was sent to it!
        uint256 ethReserve = address(this).balance - msg.value;
		// Get the balance of the other token in the contract
        uint256 tokenReserve = token.balanceOf(address(this));
		// Call the price() function to calculate how many tokens the user should receive for their ETH.
        tokenOutput = price(msg.value, ethReserve, tokenReserve);
		// Use transfer() because the contract already owns the tokens and is sending them to someone else. The transferFrom function would be used if the contract was moving tokens between two other addresses.
        require(token.transfer(msg.sender, tokenOutput), "ethToToken(): reverted swap.");
        emit EthToTokenSwap(msg.sender, tokenOutput, msg.value);
        return tokenOutput;
	}

	/**
	 * @notice sends $BAL tokens to DEX in exchange for Ether
	 */
	function tokenToEth(
		uint256 tokenInput
	) public returns (uint256 ethOutput) {
		// Make sure the value being swapped for ETH is greater than 0
		require(tokenInput > 0, "cannot swap 0 tokens");
		// Check if the user has enough tokens to swap for ETH
		require(token.balanceOf(msg.sender) >= tokenInput, "tokenToEth(): insufficient token balance");
		// Make sure the contract has enough allowance to spend the tokens
		require(token.allowance(msg.sender, address(this)) >= tokenInput, "tokenToEth(): insufficient allowance");
		// Get the balance of the other token in the contract
		uint256 tokenReserve = token.balanceOf(address(this));
		// Call the price() function to calculate how many ETH the user should receive for their tokens.
		ethOutput = price(tokenInput, tokenReserve, address(this).balance);
		// Use transferFrom() because the contract is moving tokens from one address to another. Transfer tokenInput from the user to the contract.
		require(token.transferFrom(msg.sender, address(this), tokenInput), "tokenToEth(): reverted swap.");
		// Send the ETH to the user using call for better gas handling
		(bool sent, ) = msg.sender.call{value: ethOutput}("");
		require(sent, "tokenToEth: revert in transferring eth to you!");
		// Emit the event
		emit TokenToEthSwap(msg.sender, tokenInput, ethOutput);
		// Return the amount of ETH the user received
		return ethOutput;
	}


	/**
	 * @notice allows deposits of $BAL and $ETH to liquidity pool
	 * NOTE: parameter is the msg.value sent with this function call. That amount is used to determine the amount of $BAL needed as well and taken from the depositor.
	 * NOTE: user has to make sure to give DEX approval to spend their tokens on their behalf by calling approve function prior to this function call.
	 * NOTE: Equal parts of both assets will be removed from the user's wallet with respect to the price outlined by the AMM.
	 */
	function deposit() public payable returns (uint256 tokensDeposited) {
		// Verify the sender has sent ETH
		require(msg.value > 0, "deposit: must send ETH");
		// Get ETH balance on contract before the deposit
		uint256 ethReserve = address(this).balance - msg.value;
		// Get the balance of the other token in the contract
        uint256 tokenReserve = token.balanceOf(address(this));
		// Calculate the amount of tokens the user needs to deposit
		uint256 tokenDeposit = (msg.value * tokenReserve) / ethReserve + 1;

		// Check-Effects-Interactions pattern
		// Check - Verify the sender has enough tokens to deposit
		require(token.balanceOf(msg.sender) >= tokenDeposit, "deposit: insufficient token balance");
		// Check - Verify the sender has approved the contract to spend their tokens
		require(token.allowance(msg.sender, address(this)) >= tokenDeposit, "deposit: insufficient token allowance");

		// Effects - Update the contract's state
		// Calculate the amount of liquidity tokens to mint
		uint256 liquidityMinted = msg.value * totalLiquidity / ethReserve;
		// Update the user's liquidity balance. Liquidity is a proportional share of the pool.
        liquidity[msg.sender] += liquidityMinted;
		// Update the total liquidity in the contract
        totalLiquidity += liquidityMinted;

		// Interactions - Call external contracts (e.g. token transfers)
		// Transfer tokens from the user to the contract
		require(token.transferFrom(msg.sender, address(this), tokenDeposit));
		// Emit the event
        emit LiquidityProvided(msg.sender, liquidityMinted, msg.value, tokenDeposit);
        // Return the amount of tokens the user deposited
        return tokenDeposit;
	}


	/**
	 * @notice allows withdrawal of $BAL and $ETH from liquidity pool
	 * NOTE: with this current code, the msg caller could end up getting very little back if the liquidity is super low in the pool. I guess they could see that with the UI.
	 */
	function withdraw(
		uint256 amount
	) public returns (uint256 ethAmount, uint256 tokenAmount) {
		// Verify that user is withdrawing an amount of liquidity that they actually have
		require(liquidity[msg.sender] >= amount, "withdraw: sender does not have enough liquidity to withdraw.");
		// Get the balance of both ETH and the token in the contract
		uint256 ethReserve = address(this).balance;
        uint256 tokenReserve = token.balanceOf(address(this));

		// Calculate how much of each asset our user is going withdraw 
		uint256 ethWithdrawn = amount * ethReserve / totalLiquidity; // the proportional ETH amount based on the user’s LP share.
        tokenAmount = amount * tokenReserve / totalLiquidity; // proportional token amount. tokenAmount already declared as return variable in the function signature
		
		// Update state variables
        liquidity[msg.sender] -= amount; // Decrease user liquidity by amount
        totalLiquidity -= amount;  // Decrease totalLiquidity by same amount

		// Transfer assets to the user
        (bool sent, ) = payable(msg.sender).call{ value: ethWithdrawn }("");
        require(sent, "withdraw(): revert in transferring eth to you!");
        require(token.transfer(msg.sender, tokenAmount));

		// Emit event and return values
        emit LiquidityRemoved(msg.sender, amount, tokenAmount, ethWithdrawn);
        return (ethWithdrawn, tokenAmount);
	}
}
