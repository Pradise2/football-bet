// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface PredictionMarket {
    function placeBet(uint256 marketId, uint256 outcome, uint256 amount) external;
    function claimWinnings(uint256 marketId) external returns (uint256);
}

contract MarketRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    struct BatchBet {
        address market;
        uint256 marketId;
        uint256 outcome;
        uint256 amount;
    }
    
    struct BatchClaim {
        address market;
        uint256 marketId;
    }
    
    event BatchBetPlaced(address indexed user, uint256 totalAmount, uint256 marketCount);
    event BatchClaimExecuted(address indexed user, uint256 totalClaimed, uint256 marketCount);
    
    function placeBatchBets(BatchBet[] calldata bets, IERC20 token) external nonReentrant {
        require(bets.length > 0, "No bets provided");
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < bets.length; ) {
            totalAmount += bets[i].amount;
            unchecked { i++; }
        }
        
        // Pull tokens once
        token.safeTransferFrom(msg.sender, address(this), totalAmount);

        // Track refunds
        uint256 refunded = 0;
     for (uint256 i = 0; i < bets.length; ) {
    BatchBet memory bet = bets[i];

    // Safe allowance handling
    token.forceApprove(bet.market, bet.amount);
    
    try PredictionMarket(bet.market).placeBet(bet.marketId, bet.outcome, bet.amount) {
        // success
    } catch {
        refunded += bet.amount;
        token.safeTransfer(msg.sender, bet.amount);
    }

    unchecked { i++; }
}

        
        emit BatchBetPlaced(msg.sender, totalAmount - refunded, bets.length);
    }
    
    function batchClaim(BatchClaim[] calldata claims) external nonReentrant {
        require(claims.length > 0, "No claims provided");
        
        uint256 totalClaimed = 0;
        uint256 successfulClaims = 0;
        
        for (uint256 i = 0; i < claims.length; ) {
            BatchClaim memory claim = claims[i];
            
            try PredictionMarket(claim.market).claimWinnings(claim.marketId) returns (uint256 claimed) {
                totalClaimed += claimed;
                successfulClaims++;
            } catch {
                // skip failed claim
            }

            unchecked { i++; }
        }
        
        emit BatchClaimExecuted(msg.sender, totalClaimed, successfulClaims);
    }
}
