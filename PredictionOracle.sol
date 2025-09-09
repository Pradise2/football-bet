// ===============================================
// CONTRACT 4: PredictionOracle
// ===============================================

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract PredictionOracle is Ownable {
    
    mapping(bytes32 => uint256) public results;
    mapping(bytes32 => bool) public isResolved;
    mapping(address => bool) public authorizedResolvers;
    
    // Multi-sig resolution
    mapping(bytes32 => mapping(address => uint256)) public resolverVotes;
    mapping(bytes32 => uint256) public requiredConfirmations;
    mapping(bytes32 => uint256) public confirmationCount;
    
    // Time delay for disputes
    mapping(bytes32 => uint256) public pendingResults;
    mapping(bytes32 => uint256) public resolutionTime;
    uint256 public constant DISPUTE_PERIOD = 24 hours;
    
    event ResultSet(bytes32 indexed questionId, uint256 result, address resolver);
    event ResolverAuthorized(address resolver, bool authorized);
    event DisputePeriodStarted(bytes32 indexed questionId, uint256 result, uint256 finalizeTime);
    event ResultDisputed(bytes32 indexed questionId, address disputer);
    
    modifier onlyAuthorized() {
        require(authorizedResolvers[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }
    
    function setResult(bytes32 questionId, uint256 result) external onlyAuthorized {
        require(!isResolved[questionId], "Already resolved");
        
        results[questionId] = result;
        isResolved[questionId] = true;
        
        emit ResultSet(questionId, result, msg.sender);
    }
    
    function setResultWithDelay(bytes32 questionId, uint256 result) external onlyAuthorized {
        require(!isResolved[questionId], "Already resolved");
        
        pendingResults[questionId] = result;
        resolutionTime[questionId] = block.timestamp + DISPUTE_PERIOD;
        
        emit DisputePeriodStarted(questionId, result, resolutionTime[questionId]);
    }
    
    function finalizeResult(bytes32 questionId) external {
        require(resolutionTime[questionId] > 0, "No pending result");
        require(block.timestamp >= resolutionTime[questionId], "Still in dispute period");
        require(!isResolved[questionId], "Already resolved");
        
        results[questionId] = pendingResults[questionId];
        isResolved[questionId] = true;
        
        emit ResultSet(questionId, results[questionId], msg.sender);
    }
    
    function multiSigResolve(bytes32 questionId, uint256 result) external onlyAuthorized {
        require(!isResolved[questionId], "Already resolved");
        require(requiredConfirmations[questionId] > 1, "Multi-sig not required");
        
        resolverVotes[questionId][msg.sender] = result;
        
        // Count confirmations for this result
        uint256 confirmations = 0;
        // Note: In production, you'd iterate through a list of authorized resolvers
        // This is simplified for demonstration
        
        if (confirmations >= requiredConfirmations[questionId]) {
            results[questionId] = result;
            isResolved[questionId] = true;
            emit ResultSet(questionId, result, address(this));
        }
    }
    
    function getResult(bytes32 questionId) external view returns (uint256, bool) {
        return (results[questionId], isResolved[questionId]);
    }
    
    function createQuestionId(string memory question, uint256 marketId) 
        external pure returns (bytes32) {
        return keccak256(abi.encodePacked(question, marketId));
    }
    
    function authorizeResolver(address resolver, bool authorized) external onlyOwner {
        authorizedResolvers[resolver] = authorized;
        emit ResolverAuthorized(resolver, authorized);
    }
    
    function setRequiredConfirmations(bytes32 questionId, uint256 confirmations) external onlyOwner {
        requiredConfirmations[questionId] = confirmations;
    }
    
    function disputeResult(bytes32 questionId) external {
        require(resolutionTime[questionId] > 0, "No pending result");
        require(block.timestamp < resolutionTime[questionId], "Dispute period ended");
        
        // Extend dispute period
        resolutionTime[questionId] = block.timestamp + DISPUTE_PERIOD;
        
        emit ResultDisputed(questionId, msg.sender);
    }
}