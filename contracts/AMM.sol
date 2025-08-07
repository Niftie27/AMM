//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./Token.sol";

// [X] Manage Pool
// [X] Manage Deposits
// [X] Facilitate Swaps (i.e.)
// [X] Manage Withdraws

contract AMM {
	Token public token1; // datatype is SC, var type
	Token public token2; // Token accessing SC

	uint256 public token1Balance;
	uint256 public token2Balance;
	uint256 public K;

	uint256 public totalShares;
	mapping(address => uint256) public shares;
	uint256 constant PRECISION = 10**18;

	event Swap(
		address user,
		address tokenGive,
		uint256 tokenGiveAmount,
		address tokenGet,
		uint256 tokenGetAmount,
		uint256 token2Balance,
		uint256 token1Balance,
		uint256 timestamp
	);

	constructor(Token _token1, Token _token2) {
		token1 = _token1;
		token2 = _token2;
	}

	function addLiquidity(uint256 _token1Amount, uint256 _token2Amount) external {
		// Deposit Tokens
		require(
			token1.transferFrom(msg.sender, address(this), _token1Amount),
			"failed to transfer token 1"
		);
		require(
			token2.transferFrom(msg.sender, address(this), _token2Amount),
			"failed to transfer token 2"
		);

		// Issue Shares
		uint256 share;

		// If first time adding liq, make share 100
		if (totalShares == 0) {
			share = 100 * PRECISION;
		} else {
			uint256 share1 = (totalShares * _token1Amount) / token1Balance;
			uint256 share2 = (totalShares * _token2Amount) / token2Balance;
			require(
				(share1 / 10**3) == (share2 / 10**3),
				"must provide equal token amounts"
			);
			share = share1;
		}

		// Manage Pool
		token1Balance += _token1Amount;
		token2Balance += _token2Amount;
		K = token1Balance * token2Balance;

		// Update shares
		totalShares += share;
		shares[msg.sender] += share;

	}

	// Determine how many token2 tokens must be deposited when depositing liquidity for token1
	function calculateToken2Deposit(uint _token1Amount) public view returns(uint256 token2Amount) {
		token2Amount = (token2Balance * _token1Amount) / token1Balance;
	}


	// Determine how many token1 tokens must be deposited when depositing liquidity for token2
	function calculateToken1Deposit(uint _token2Amount) public view returns(uint256 token1Amount) {
		token1Amount = (token1Balance * _token2Amount) / token2Balance;
	}

	// Returns amount of token2 received when swapping token1
	function calculateToken1Swap(uint256 _token1Amount) 
		public
		view
		returns (uint256 token2Amount)
	{
		uint256 token1After = token1Balance + _token1Amount; // increases token1 in the pool
		uint256 token2After = K / token1After; // K = token1 * token2 - This is key to pricing
		token2Amount = token2Balance - token2After; // how much token2 is leaving the pool

		// Don't let pool go to 0
		if(token2Amount == token2Balance) {
			token2Amount --;
		}

		require(token2Amount < token2Balance, "swap cannot exceed pool balance");
	}

	// Calculate Token 2 Amount
	function swapToken1(uint256 _token1Amount)
		external 
		returns(uint256 token2Amount)
	{
		// Calculate Token 2 Amount
		token2Amount = calculateToken1Swap(_token1Amount);

		// Do Swap (from perspective of SC, so don't have to approve)
		// 1. Transfer tokens out of user wallet
		token1.transferFrom(msg.sender, address(this), _token1Amount);
		// 2. Update the token balance in the contract
		token1Balance += _token1Amount;
		// 3. Update token2 balance in the contract
		token2Balance -= token2Amount;
		// 4. Transfer token2 tokens from contract to user wallet
		token2.transfer(msg.sender, token2Amount);
		


		// Emit an event
		emit Swap(
			msg.sender,
			address(token1),
			_token1Amount,
			address(token2),
			token2Amount,
			token1Balance,
			token2Balance,
			block.timestamp
		);
	}

	/*
		event Swap(
		address user,
		address tokenGive,
		uint256 tokenGiveAmount,
		address tokenGet,
		uint256 tokenGetAmount,
		uint256 token2Balance,
		uint256 token1Balance
		uint256 timestamp
	);
	*/

	// Returns amount of token2 received when swapping token1
	function calculateToken2Swap(uint256 _token2Amount) 
		public
		view
		returns(uint256 token1Amount)
	{
		uint256 token2After = token2Balance + _token2Amount;
		uint256 token1After = K / token2After;					// This is key to pricing
		token1Amount = token1Balance - token1After;

		// Don't let pool go to 0
		if(token1Amount == token1Balance) {
			token1Amount --;
		}

		require(token1Amount < token1Balance, "swap cannot exceed pool balance");
	}


	// Calculate Token 1 Amount
	function swapToken2(uint256 _token2Amount)
		external 
		returns(uint256 token1Amount)
	{
		// Calculate Token 1 Amount
		token1Amount = calculateToken2Swap(_token2Amount);

		// Do Swap (from perspective of SC, so don't have to approve)
		// 1. Transfer tokens out of user wallet
		token2.transferFrom(msg.sender, address(this), _token2Amount);
		// 2. Update the token balance in the contract
		token2Balance += _token2Amount; // goes up
		// 3. Update token1 balance in the contract
		token1Balance -= token1Amount; // goes down
		// 4. Transfer token1 tokens from contract to user wallet
		token1.transfer(msg.sender, token1Amount); // token1 transfer to user's wallet


	
	emit Swap(
			msg.sender,
			address(token2),
			_token2Amount,
			address(token1),
			token1Amount,
			token2Balance,
			token1Balance,
			block.timestamp
		);	
	}

	function calculateWithdrawAmount(uint _share) public view returns(uint256 token1Amount, uint256 token2Amount) {
		require(_share <= totalShares, "must be less than total shares");
		token1Amount = (_share * token1Balance) / totalShares;
		token2Amount = (_share * token2Balance) / totalShares;
	}

	// Removes liquidity from the pool
	function removeLiquidity(uint256 _share) external returns(uint256 token1Amount, uint256 token2Amount) {
		require(
			_share <= shares[msg.sender],
			"cannot withdraw more shares than you have"
		);

		(token1Amount, token2Amount) = calculateWithdrawAmount(_share); // paralel assignment

		shares[msg.sender] -= _share; 	// changes mapping
		totalShares -= _share;			// changes state var

		token1Balance -= token1Amount;		// changes balance
		token2Balance -= token2Amount;		// changes balance
		K = token1Balance * token2Balance;	// we need to change K for determining prices whenever swap 
		// (K is not true constant, but it is a constant; traders don't change it, but liq. providers change it)

		// transfer funds back to user
		token1.transfer(msg.sender, token1Amount);
		token2.transfer(msg.sender, token2Amount);

	}

}