// ===============================================
// CONTRACT 10: LiquidityPool
// ===============================================

contract LiquidityPool is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;
    
    IERC20 public baseToken;
    mapping(address => uint256) public liquidityProvided;
    mapping(address => uint256) public shares;
    
    uint256 public totalLiquidity;
    uint256 public totalShares;
    uint256 public feeRate = 100;
    
    struct PoolMarket {
        address market;
        uint256 allocation;
        bool active;
    }
    
    PoolMarket[] public poolMarkets;
    mapping(address => uint256) public marketIndex;
    
    event LiquidityAdded(address indexed provider, uint256 amount, uint256 shares);
    event LiquidityRemoved(address indexed provider, uint256 amount, uint256 shares);
    event MarketAdded(address indexed market, uint256 allocation);
    
    constructor(address _baseToken) {
        baseToken = IERC20(_baseToken);
    }
    
    function addLiquidity(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be positive");
        
        baseToken.safeTransferFrom(msg.sender, address(this), amount);
        
        uint256 newShares;
        if (totalShares == 0) {
            newShares = amount;
        } else {
            newShares = (amount * totalShares) / totalLiquidity;
        }
        
        liquidityProvided[msg.sender] += amount;
        shares[msg.sender] += newShares;
        totalLiquidity += amount;
        totalShares += newShares;
        
        emit LiquidityAdded(msg.sender, amount, newShares);
    }
    
    function removeLiquidity(uint256 shareAmount) external nonReentrant {
        require(shares[msg.sender] >= shareAmount, "Insufficient shares");
        
        uint256 amount = (shareAmount * totalLiquidity) / totalShares;
        
        shares[msg.sender] -= shareAmount;
        totalShares -= shareAmount;
        totalLiquidity -= amount;
        
        baseToken.safeTransfer(msg.sender, amount);
        
        emit LiquidityRemoved(msg.sender, amount, shareAmount);
    }
    
    function addMarket(address market, uint256 allocation) external onlyOwner {
        require(allocation > 0 && allocation <= 10000, "Invalid allocation");
        
        poolMarkets.push(PoolMarket({
            market: market,
            allocation: allocation,
            active: true
        }));
        
        marketIndex[market] = poolMarkets.length - 1;
        
        emit MarketAdded(market, allocation);
    }
}