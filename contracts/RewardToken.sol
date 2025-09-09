// SPDX-License-Identifier: MIT


// ===============================================
// CONTRACT 2: RewardToken (ABT)
// ===============================================

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract RewardToken is ERC20, ERC20Burnable, Ownable {
    
    mapping(address => bool) public minters;
    uint256 public constant MAX_SUPPLY = 100_000_000 * 1e18;
    
    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    
    constructor() ERC20("ArbBet Token", "ABT") {
        _mint(msg.sender, 10_000_000 * 1e18);
    }
    
    modifier onlyMinter() {
        require(minters[msg.sender] || msg.sender == owner(), "Not a minter");
        _;
    }
    
    function mint(address to, uint256 amount) external onlyMinter {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount);
    }
    
    function addMinter(address minter) external onlyOwner {
        minters[minter] = true;
        emit MinterAdded(minter);
    }
    
    function removeMinter(address minter) external onlyOwner {
        minters[minter] = false;
        emit MinterRemoved(minter);
    }
}