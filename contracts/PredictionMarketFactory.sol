
// ===============================================
// CONTRACT 6: PredictionMarketFactory
// ===============================================

contract PredictionMarketFactory is Ownable, Pausable {
    
    event MarketDeployed(address indexed marketAddress, address indexed creator, string name, address bettingToken);
    
    address[] public deployedMarkets;
    mapping(address => bool) public isValidMarket;
    mapping(address => address[]) public userCreatedMarkets;
    
    struct MarketParams {
        string name;
        address bettingToken;
        uint256 platformFee;
    }
    
    function createMarket(MarketParams memory params) external whenNotPaused returns (address) {
        require(bytes(params.name).length > 0, "Name required");
        require(params.bettingToken != address(0), "Invalid token");
        require(params.platformFee <= 1000, "Fee too high");
        
        PredictionMarket market = new PredictionMarket(params.bettingToken);
        market.transferOwnership(msg.sender);
        
        if (params.platformFee > 0) {
            market.setPlatformFee(params.platformFee);
        }
        
        deployedMarkets.push(address(market));
        isValidMarket[address(market)] = true;
        userCreatedMarkets[msg.sender].push(address(market));
        
        emit MarketDeployed(address(market), msg.sender, params.name, params.bettingToken);
        return address(market);
    }
    
    function getDeployedMarkets() external view returns (address[] memory) {
        return deployedMarkets;
    }
    
    function getUserMarkets(address user) external view returns (address[] memory) {
        return userCreatedMarkets[user];
    }
    
    function getMarketCount() external view returns (uint256) {
        return deployedMarkets.length;
    }
}
