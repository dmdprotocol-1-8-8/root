// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title DMDToken - Extreme Deflationary Digital Asset
/// @dev Dual minter: MintDistributor (emissions) + VestingContract (team allocation)
/// @dev Public burn, 18M max supply, fully decentralized
/// @dev Tracks unique holder count for PDC activation threshold
/// @dev v1.8.8 - Final version, gas optimized
contract DMDToken {
    error Unauthorized();
    error ExceedsMaxSupply();
    error InsufficientBalance();
    error InvalidAmount();
    error InvalidRecipient();

    string public constant name = "DMD Protocol";
    string public constant symbol = "DMD";
    uint8 public constant decimals = 18;
    uint256 public constant MAX_SUPPLY = 18_000_000e18;
    uint256 public constant MIN_HOLDER_BALANCE = 100e18;  // 100 DMD minimum to count as holder

    address public immutable MINT_DISTRIBUTOR;
    address public immutable VESTING_CONTRACT;
    uint256 public totalMinted;
    uint256 public totalBurned;

    // Unique holder tracking for PDC activation
    // Once an address qualifies as a holder (balance >= 100 DMD), they're counted permanently
    // This prevents oscillation attacks where users repeatedly cross the threshold
    uint256 public uniqueHolderCount;
    mapping(address => bool) private _wasEverHolder;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(address _mintDistributor, address _vestingContract) {
        if (_mintDistributor == address(0) || _vestingContract == address(0)) revert InvalidRecipient();
        MINT_DISTRIBUTOR = _mintDistributor;
        VESTING_CONTRACT = _vestingContract;
    }

    function totalSupply() public view returns (uint256) { return totalMinted - totalBurned; }

    function mint(address to, uint256 amount) external {
        if (msg.sender != MINT_DISTRIBUTOR && msg.sender != VESTING_CONTRACT) revert Unauthorized();
        if (to == address(0)) revert InvalidRecipient();
        if (amount == 0) revert InvalidAmount();
        if (totalMinted + amount > MAX_SUPPLY) revert ExceedsMaxSupply();

        totalMinted += amount;
        balanceOf[to] += amount;

        // Track new holder AFTER balance update (only if balance >= MIN_HOLDER_BALANCE)
        // Each address can only increment uniqueHolderCount once (prevents oscillation attack)
        if (!_wasEverHolder[to] && balanceOf[to] >= MIN_HOLDER_BALANCE) {
            _wasEverHolder[to] = true;
            uniqueHolderCount++;
        }

        emit Transfer(address(0), to, amount);
    }

    function burn(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();

        balanceOf[msg.sender] -= amount;
        totalBurned += amount;

        emit Transfer(msg.sender, address(0), amount);
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        if (to == address(0)) revert InvalidRecipient();
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();

        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;

        // Track new holder AFTER balance update
        if (!_wasEverHolder[to] && balanceOf[to] >= MIN_HOLDER_BALANCE) {
            _wasEverHolder[to] = true;
            uniqueHolderCount++;
        }

        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        if (to == address(0)) revert InvalidRecipient();

        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientBalance();
            allowance[from][msg.sender] = allowed - amount;
        }

        if (balanceOf[from] < amount) revert InsufficientBalance();

        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        // Track new holder AFTER balance update
        if (!_wasEverHolder[to] && balanceOf[to] >= MIN_HOLDER_BALANCE) {
            _wasEverHolder[to] = true;
            uniqueHolderCount++;
        }

        emit Transfer(from, to, amount);
        return true;
    }
}
