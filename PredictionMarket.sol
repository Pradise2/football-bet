// ===============================================
// CONTRACT 5: PredictionMarket (Main Contract)
// ===============================================
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract PredictionMarket is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    enum MarketStatus { Active, Resolved, Cancelled }
    enum Category { Sports, Crypto, Politics, Entertainment, Technology, Other }
    
    struct Market {
        uint256 id;
        string title;
        string description;
        string imageUrl;
        Category category;
        address creator;
        uint256 creationTime;
        uint256 endTime;
        uint256 resolutionTime;
        MarketStatus status;
        string[] outcomes;
        uint256 totalVolume;
        uint256 creatorFee;
        bool resolved;
        uint256 winningOutcome;
        bool oracleResolution;
        string oracleQuestion;
        mapping(uint256 => uint256) outcomeShares;
        mapping(uint256 => uint256) outcomeVolume;
        mapping(address => mapping(uint256 => Position)) userPositions;
    }

    struct Position {
        uint256 marketId;
        uint256 outcome;
        uint256 shares;
        uint256 avgPrice;
        uint256 totalPaid;
        bool claimed;
    }

    struct UserActivity {
        uint256 timestamp;
        string activityType;
        uint256 marketId;
        uint256 amount;
        string details;
    }

    mapping(uint256 => Market) public markets;
    mapping(address => UserActivity[]) public userActivities;
    mapping(address => uint256) public userTotalVolume;
    mapping(Category => uint256[]) public marketsByCategory;
    
    uint256 public marketCounter;
    uint256 public totalPlatformVolume;
    uint256 public totalMarkets;
    uint256 public totalUsers;
    uint256 public platformFee = 200;
    uint256 public constant MAX_OUTCOMES = 10;
    uint256 public constant MIN_MARKET_DURATION = 1 hours;
    uint256 public constant MAX_MARKET_DURATION = 365 days;
    
    IERC20 public bettingToken;
    address public oracleContract;
    address public hubContract;
    
    event MarketCreated(uint256 indexed marketId, address indexed creator, string title, Category category, uint256 endTime);
    event BetPlaced(uint256 indexed marketId, address indexed user, uint256 indexed outcome, uint256 amount, uint256 shares, uint256 price);
    event MarketResolved(uint256 indexed marketId, uint256 winningOutcome, uint256 totalVolume);
    event WinningsClaimed(uint256 indexed marketId, address indexed user, uint256 amount);
    event MarketCancelled(uint256 indexed marketId, string reason);

    constructor(address _bettingToken) {
        bettingToken = IERC20(_bettingToken);
    }

    function createMarket(
        string memory _title,
        string memory _description,
        string memory _imageUrl,
        Category _category,
        uint256 _endTime,
        string[] memory _outcomes,
        uint256 _creatorFee,
        bool _useOracle,
        string memory _oracleQuestion
    ) external whenNotPaused returns (uint256) {
        require(_outcomes.length >= 2 && _outcomes.length <= MAX_OUTCOMES, "Invalid outcomes count");
        require(_endTime > block.timestamp + MIN_MARKET_DURATION, "End time too soon");
        require(_endTime < block.timestamp + MAX_MARKET_DURATION, "End time too far");
        require(_creatorFee <= 1000, "Creator fee too high");
        require(bytes(_title).length > 0, "Title required");

        uint256 marketId = ++marketCounter;
        Market storage market = markets[marketId];
        
        market.id = marketId;
        market.title = _title;
        market.description = _description;
        market.imageUrl = _imageUrl;
        market.category = _category;
        market.creator = msg.sender;
        market.creationTime = block.timestamp;
        market.endTime = _endTime;
        market.status = MarketStatus.Active;
        market.outcomes = _outcomes;
        market.creatorFee = _creatorFee;
        market.oracleResolution = _useOracle;
        market.oracleQuestion = _oracleQuestion;
        
        marketsByCategory[_category].push(marketId);
        totalMarkets++;
        
        _recordActivity(msg.sender, "create", marketId, 0, _title);
        
        emit MarketCreated(marketId, msg.sender, _title, _category, _endTime);
        return marketId;
    }

    function placeBet(uint256 _marketId, uint256 _outcome, uint256 _amount) external nonReentrant whenNotPaused {
        Market storage market = markets[_marketId];
        require(market.status == MarketStatus.Active, "Market not active");
        require(block.timestamp < market.endTime, "Market ended");
        require(_outcome < market.outcomes.length, "Invalid outcome");
        require(_amount > 0, "Amount must be positive");

        bettingToken.safeTransferFrom(msg.sender, address(this), _amount);
        
        uint256 shares = _calculateShares(_marketId, _outcome, _amount);
        
        Position storage position = market.userPositions[msg.sender][_outcome];
        uint256 newTotalPaid = position.totalPaid + _amount;
        uint256 newShares = position.shares + shares;
        
        if (newShares > 0) {
            position.avgPrice = newTotalPaid * 1e18 / newShares;
        }
        position.shares = newShares;
        position.totalPaid = newTotalPaid;
        position.marketId = _marketId;
        position.outcome = _outcome;

        market.totalVolume += _amount;
        market.outcomeShares[_outcome] += shares;
        market.outcomeVolume[_outcome] += _amount;
        
        totalPlatformVolume += _amount;
        userTotalVolume[msg.sender] += _amount;
        
        _recordActivity(msg.sender, "bet", _marketId, _amount, 
                       string(abi.encodePacked("Bet on: ", market.outcomes[_outcome])));
        
        // Notify hub contract if connected
        if (hubContract != address(0)) {
            (bool success,) = hubContract.call(
                abi.encodeWithSignature("onBetPlaced(address,uint256,uint256,uint256)", msg.sender, _marketId, _outcome, _amount)
            );
        }
        
        uint256 price = shares > 0 ? _amount * 1e18 / shares : 1e18;
        emit BetPlaced(_marketId, msg.sender, _outcome, _amount, shares, price);
    }

    function resolveMarket(uint256 _marketId, uint256 _winningOutcome) external {
        Market storage market = markets[_marketId];
        require(market.creator == msg.sender || owner() == msg.sender, "Not authorized");
        require(market.status == MarketStatus.Active, "Market not active");
        require(block.timestamp >= market.endTime, "Market not ended");
        require(_winningOutcome < market.outcomes.length, "Invalid outcome");
        require(!market.resolved, "Already resolved");

        market.status = MarketStatus.Resolved;
        market.resolved = true;
        market.winningOutcome = _winningOutcome;
        market.resolutionTime = block.timestamp;

        // Notify hub contract if connected
        if (hubContract != address(0)) {
            (bool success,) = hubContract.call(
                abi.encodeWithSignature("onMarketResolved(uint256,uint256)", _marketId, _winningOutcome)
            );
        }

        emit MarketResolved(_marketId, _winningOutcome, market.totalVolume);
    }

    function requestOracleResolution(uint256 _marketId) external {
        Market storage market = markets[_marketId];
        require(market.oracleResolution, "Oracle not enabled");
        require(block.timestamp >= market.endTime, "Market not ended");
        require(!market.resolved, "Already resolved");
        
        if (oracleContract != address(0)) {
            bytes32 questionId = keccak256(abi.encodePacked(market.oracleQuestion, _marketId));
            // Oracle integration would happen here
        }
    }

    function claimWinnings(uint256 _marketId) external nonReentrant {
        Market storage market = markets[_marketId];
        require(market.resolved, "Market not resolved");
        
        uint256 winningOutcome = market.winningOutcome;
        Position storage position = market.userPositions[msg.sender][winningOutcome];
        require(position.shares > 0, "No winning position");
        require(!position.claimed, "Already claimed");

        uint256 totalWinningShares = market.outcomeShares[winningOutcome];
        require(totalWinningShares > 0, "No winning shares");
        
        uint256 totalPayout = market.totalVolume;
        uint256 platformFeeAmount = (totalPayout * platformFee) / 10000;
        uint256 creatorFeeAmount = (totalPayout * market.creatorFee) / 10000;
        uint256 netPayout = totalPayout - platformFeeAmount - creatorFeeAmount;
        
        uint256 userPayout = (position.shares * netPayout) / totalWinningShares;
        
        position.claimed = true;
        
        if (userPayout > 0) {
            bettingToken.safeTransfer(msg.sender, userPayout);
        }
        
        if (creatorFeeAmount > 0) {
            bettingToken.safeTransfer(market.creator, creatorFeeAmount);
        }
        
        _recordActivity(msg.sender, "claim", _marketId, userPayout, "Claimed winnings");
        
        // Notify hub contract
        if (hubContract != address(0)) {
            (bool success,) = hubContract.call(
                abi.encodeWithSignature("onWinningsClaimed(address,uint256,uint256)", msg.sender, _marketId, userPayout)
            );
        }
        
        emit WinningsClaimed(_marketId, msg.sender, userPayout);
    }

    // View Functions
    function getMarket(uint256 _marketId) external view returns (
        uint256 id,
        string memory title,
        string memory description,
        string memory imageUrl,
        Category category,
        address creator,
        uint256 creationTime,
        uint256 endTime,
        uint256 resolutionTime,
        MarketStatus status,
        string[] memory outcomes,
        uint256 totalVolume,
        uint256 creatorFee,
        bool resolved,
        uint256 winningOutcome,
        bool oracleResolution
    ) {
        Market storage market = markets[_marketId];
        return (
            market.id,
            market.title,
            market.description,
            market.imageUrl,
            market.category,
            market.creator,
            market.creationTime,
            market.endTime,
            market.resolutionTime,
            market.status,
            market.outcomes,
            market.totalVolume,
            market.creatorFee,
            market.resolved,
            market.winningOutcome,
            market.oracleResolution
        );
    }

    function getMarketOdds(uint256 _marketId) external view returns (
        uint256[] memory prices,
        uint256[] memory percentages,
        uint256[] memory volumes
    ) {
        Market storage market = markets[_marketId];
        uint256 outcomeCount = market.outcomes.length;
        
        prices = new uint256[](outcomeCount);
        percentages = new uint256[](outcomeCount);
        volumes = new uint256[](outcomeCount);
        
        uint256 totalShares = 0;
        for (uint256 i = 0; i < outcomeCount; i++) {
            totalShares += market.outcomeShares[i];
            volumes[i] = market.outcomeVolume[i];
        }
        
        for (uint256 i = 0; i < outcomeCount; i++) {
            if (totalShares > 0) {
                percentages[i] = (market.outcomeShares[i] * 100 * 1e18) / totalShares;
                prices[i] = _calculatePrice(_marketId, i);
            } else {
                percentages[i] = (100 * 1e18) / outcomeCount;
                prices[i] = 1e18;
            }
        }
    }

    function getUserPosition(address _user, uint256 _marketId, uint256 _outcome) 
        external view returns (Position memory) {
        return markets[_marketId].userPositions[_user][_outcome];
    }

    function getUserActivity(address _user, uint256 _limit) 
        external view returns (UserActivity[] memory) {
        UserActivity[] storage activities = userActivities[_user];
        uint256 length = activities.length;
        uint256 returnLength = _limit > 0 && _limit < length ? _limit : length;
        
        UserActivity[] memory result = new UserActivity[](returnLength);
        
        for (uint256 i = 0; i < returnLength; i++) {
            result[i] = activities[length - 1 - i];
        }
        
        return result;
    }

    function getTrendingMarkets(uint256 _limit) external view returns (uint256[] memory) {
        uint256[] memory trendingIds = new uint256[](_limit);
        uint256 count = 0;
        
        for (uint256 i = marketCounter; i > 0 && count < _limit; i--) {
            Market storage market = markets[i];
            if (market.status == MarketStatus.Active && 
                block.timestamp < market.endTime &&
                market.totalVolume > 0) {
                trendingIds[count] = i;
                count++;
            }
        }
        
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = trendingIds[i];
        }
        
        return result;
    }

    function getPlatformStats() external view returns (
        uint256 _totalVolume,
        uint256 _totalMarkets,
        uint256 _totalUsers,
        uint256 _activeMarkets
    ) {
        uint256 activeCount = 0;
        for (uint256 i = 1; i <= marketCounter; i++) {
            if (markets[i].status == MarketStatus.Active) {
                activeCount++;
            }
        }
        
        return (totalPlatformVolume, totalMarkets, totalUsers, activeCount);
    }

    function getMarketsByCategory(Category _category, uint256 _limit) 
        external view returns (uint256[] memory) {
        uint256[] storage categoryMarkets = marketsByCategory[_category];
        uint256 length = categoryMarkets.length;
        uint256 returnLength = _limit > 0 && _limit < length ? _limit : length;
        
        uint256[] memory result = new uint256[](returnLength);
        
        for (uint256 i = 0; i < returnLength; i++) {
            result[i] = categoryMarkets[length - 1 - i];
        }
        
        return result;
    }

    // Internal functions
    function _calculateShares(uint256 _marketId, uint256 _outcome, uint256 _amount) 
        internal view returns (uint256) {
        Market storage market = markets[_marketId];
        uint256 currentShares = market.outcomeShares[_outcome];
        
        if (currentShares == 0) {
            return _amount;
        }
        
        uint256 price = _calculatePrice(_marketId, _outcome);
        return (_amount * 1e18) / price;
    }

    function _calculatePrice(uint256 _marketId, uint256 _outcome) 
        internal view returns (uint256) {
        Market storage market = markets[_marketId];
        uint256 totalShares = 0;
        
        for (uint256 i = 0; i < market.outcomes.length; i++) {
            totalShares += market.outcomeShares[i];
        }
        
        if (totalShares == 0) {
            return 1e18;
        }
        
        uint256 outcomeShares = market.outcomeShares[_outcome];
        return 1e18 + (outcomeShares * 5e17) / (totalShares + 1);
    }

    function _recordActivity(
        address _user, 
        string memory _type, 
        uint256 _marketId, 
        uint256 _amount, 
        string memory _details
    ) internal {
        userActivities[_user].push(UserActivity({
            timestamp: block.timestamp,
            activityType: _type,
            marketId: _marketId,
            amount: _amount,
            details: _details
        }));
        
        if (userActivities[_user].length == 1) {
            totalUsers++;
        }
    }

    // Admin functions
    function setHubContract(address _hubContract) external onlyOwner {
        hubContract = _hubContract;
    }

    function setOracleContract(address _oracleContract) external onlyOwner {
        oracleContract = _oracleContract;
    }

    function setPlatformFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 1000, "Fee too high");
        platformFee = _newFee;
    }

    function cancelMarket(uint256 _marketId, string memory _reason) external {
        Market storage market = markets[_marketId];
        require(market.creator == msg.sender || owner() == msg.sender, "Not authorized");
        require(market.status == MarketStatus.Active, "Market not active");
        
        market.status = MarketStatus.Cancelled;
        emit MarketCancelled(_marketId, _reason);
    }

    function withdrawPlatformFees() external onlyOwner {
        uint256 balance = bettingToken.balanceOf(address(this));
        bettingToken.safeTransfer(owner(), balance / 10);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw(address _token) external onlyOwner {
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(owner(), balance);
    }
}