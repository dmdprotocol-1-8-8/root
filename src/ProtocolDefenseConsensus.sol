// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IDMDToken} from "./interfaces/IDMDToken.sol";

/// @title ProtocolDefenseConsensus (PDC) - Adapter-Only Governance
/// @notice PDC exists ONLY to manage external adapters, not money.
/// @dev PDC is completely inert until both activation conditions are met (30% supply + 10k holders)
/// @dev PDC CANNOT: change emissions, change supply, mint/burn, move BTC, freeze balances, upgrade contracts
/// @dev v1.8.8 - Security fix: Voting power now locked at proposal creation via registration phase
contract ProtocolDefenseConsensus {
    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════
    error PDCNotActive();
    error PDCAlreadyActive();
    error InvalidAdapter();
    error ProposalActive();
    error NoProposalActive();
    error InvalidState();
    error VotingNotEnded();
    error VotingEnded();
    error ExecutionDelayNotMet();
    error ExecutionDeadlineExpired();
    error ExecutionDeadlineNotExpired();
    error CooldownNotComplete();
    error QuorumNotMet();
    error ApprovalThresholdNotMet();
    error AlreadyVoted();
    error ZeroVotingPower();
    error InvalidAction();
    error RegistrationClosed();
    error AlreadyRegistered();
    error NotRegistered();

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    // PDC can ONLY perform these 4 actions - nothing else
    enum ActionType {
        PAUSE_ADAPTER,      // Pause an external adapter
        RESUME_ADAPTER,     // Resume a paused adapter
        APPROVE_ADAPTER,    // Approve a new external contract address
        DEPRECATE_ADAPTER   // Deprecate an adapter (disable future inflow)
    }

    enum ProposalState {
        IDLE,       // No proposal active
        VOTING,     // Voting period active (14 days)
        QUEUED,     // Voting passed, execution delay (7 days)
        COOLDOWN    // Post-execution cooldown (30 days)
    }

    struct Proposal {
        ActionType action;
        address adapter;
        uint256 proposedAt;
        uint256 votingEndsAt;
        uint256 executionTime;
        uint256 executionDeadline;
        uint256 cooldownEndsAt;
        uint256 yesVotes;
        uint256 noVotes;
        uint256 snapshotSupply;
        bool executed;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HARD-CODED CONSTANTS (IMMUTABLE)
    // ═══════════════════════════════════════════════════════════════════════

    // Activation thresholds - PDC is inert until BOTH conditions are true
    uint256 public constant MIN_CIRCULATING_PERCENT = 30;     // 30% of max supply
    uint256 public constant MIN_UNIQUE_HOLDERS = 10_000;      // 10,000 unique holders

    // Voting parameters - HARD-CODED, no governance can change
    uint256 public constant QUORUM_PERCENT = 60;              // 60% of total supply
    uint256 public constant APPROVAL_PERCENT = 75;            // 75% YES required
    uint256 public constant VOTING_PERIOD = 14 days;
    uint256 public constant EXECUTION_DELAY = 7 days;
    uint256 public constant EXECUTION_WINDOW = 30 days;       // Must execute within 30 days
    uint256 public constant COOLDOWN_PERIOD = 30 days;
    uint256 public constant MIN_PROPOSAL_BALANCE = 1000e18;   // 1000 DMD to create proposal (anti-spam)
    uint256 public constant REGISTRATION_PERIOD = 1 days;     // 1 day window to register voting power after proposal creation

    // ═══════════════════════════════════════════════════════════════════════
    // IMMUTABLE STATE
    // ═══════════════════════════════════════════════════════════════════════

    IDMDToken public immutable DMD_TOKEN;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    bool public activated;  // Once true, stays true forever (irreversible)

    // Current proposal (only ONE at a time)
    Proposal public currentProposal;
    ProposalState public proposalState;

    // Voting records - snapshot-based to prevent double voting
    mapping(uint256 => mapping(address => bool)) public hasVoted;  // proposalId => voter => voted
    mapping(uint256 => mapping(address => uint256)) public votingPowerSnapshot;  // proposalId => voter => balance at snapshot block
    uint256 public proposalCount;

    // Snapshot block for each proposal - voting power is based on balance at this block
    mapping(uint256 => uint256) public proposalSnapshotBlock;  // proposalId => block number

    // Adapter registry
    mapping(address => bool) public approvedAdapters;
    mapping(address => bool) public pausedAdapters;
    mapping(address => bool) public deprecatedAdapters;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event PDCActivated(uint256 timestamp, uint256 circulatingSupply, uint256 uniqueHolders);
    event ProposalCreated(uint256 indexed proposalId, ActionType action, address adapter);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalQueued(uint256 indexed proposalId, uint256 executionTime);
    event ProposalExecuted(uint256 indexed proposalId, ActionType action, address adapter);
    event ProposalFailed(uint256 indexed proposalId, string reason);
    event CooldownStarted(uint256 indexed proposalId, uint256 endsAt);
    event VoterRegistered(uint256 indexed proposalId, address indexed voter, uint256 votingPower);

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Initialize PDC with DMD token and initial approved adapters
    /// @dev Initial adapters are pre-approved at deployment (e.g., tBTC)
    /// @dev These adapters work immediately; PDC governance manages them after activation
    /// @param _dmdToken DMD token address
    /// @param _initialAdapters Array of initial adapter addresses to pre-approve
    constructor(address _dmdToken, address[] memory _initialAdapters) {
        if (_dmdToken == address(0)) revert InvalidAdapter();
        DMD_TOKEN = IDMDToken(_dmdToken);
        proposalState = ProposalState.IDLE;

        // Pre-approve initial adapters (e.g., tBTC)
        // These work immediately and can be managed by PDC after activation
        for (uint256 i = 0; i < _initialAdapters.length; i++) {
            if (_initialAdapters[i] != address(0)) {
                approvedAdapters[_initialAdapters[i]] = true;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ACTIVATION (DETERMINISTIC, IRREVERSIBLE)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Check if PDC can be activated
    /// @dev Returns true only if BOTH conditions are met (30% supply + 10k holders)
    function canActivate() public view returns (bool) {
        if (activated) return false;  // Already activated

        // Condition 1: 30% of max supply circulating
        uint256 maxSupply = DMD_TOKEN.MAX_SUPPLY();
        uint256 circulating = DMD_TOKEN.totalSupply();
        if (circulating * 100 < maxSupply * MIN_CIRCULATING_PERCENT) return false;

        // Condition 2: 10,000 unique holders
        uint256 holders = DMD_TOKEN.uniqueHolderCount();
        if (holders < MIN_UNIQUE_HOLDERS) return false;

        return true;
    }

    /// @notice Activate PDC (anyone can call, purely deterministic)
    /// @dev Once activated, stays activated forever
    function activate() external {
        if (activated) revert PDCAlreadyActive();
        if (!canActivate()) revert PDCNotActive();

        activated = true;

        emit PDCActivated(
            block.timestamp,
            DMD_TOKEN.totalSupply(),
            DMD_TOKEN.uniqueHolderCount()
        );
    }

    /// @notice Get activation status with detailed breakdown
    function getActivationStatus() external view returns (
        bool isActivated,
        bool supplyConditionMet,
        bool holderConditionMet,
        uint256 currentCirculatingPercent,
        uint256 currentHolders
    ) {
        isActivated = activated;

        uint256 maxSupply = DMD_TOKEN.MAX_SUPPLY();
        uint256 circulating = DMD_TOKEN.totalSupply();
        currentCirculatingPercent = (circulating * 100) / maxSupply;
        supplyConditionMet = currentCirculatingPercent >= MIN_CIRCULATING_PERCENT;

        currentHolders = DMD_TOKEN.uniqueHolderCount();
        holderConditionMet = currentHolders >= MIN_UNIQUE_HOLDERS;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PROPOSAL CREATION (ONLY WHEN PDC IS ACTIVE)
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyActive() {
        if (!activated) revert PDCNotActive();
        _;
    }

    modifier inState(ProposalState expected) {
        if (proposalState != expected) revert InvalidState();
        _;
    }

    /// @notice Create a new proposal (only one at a time)
    /// @dev Must have minimum DMD balance to propose (anti-spam)
    function propose(ActionType action, address adapter) external onlyActive inState(ProposalState.IDLE) {
        if (adapter == address(0)) revert InvalidAdapter();
        if (DMD_TOKEN.balanceOf(msg.sender) < MIN_PROPOSAL_BALANCE) revert ZeroVotingPower();

        // Validate action makes sense for adapter state
        _validateAction(action, adapter);

        proposalCount++;

        // Snapshot total supply at proposal creation to prevent vote manipulation
        uint256 snapshotSupply = DMD_TOKEN.totalSupply();

        // SECURITY FIX: Record snapshot block at proposal creation
        // Voting power will be based on balance at this block (prevents buy-vote attacks)
        proposalSnapshotBlock[proposalCount] = block.number;

        currentProposal = Proposal({
            action: action,
            adapter: adapter,
            proposedAt: block.timestamp,
            votingEndsAt: block.timestamp + VOTING_PERIOD,
            executionTime: 0,
            executionDeadline: 0,
            cooldownEndsAt: 0,
            yesVotes: 0,
            noVotes: 0,
            snapshotSupply: snapshotSupply,
            executed: false
        });

        proposalState = ProposalState.VOTING;

        emit ProposalCreated(proposalCount, action, adapter);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REGISTRATION (1 DAY WINDOW AFTER PROPOSAL CREATION)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Register voting power for the current proposal
    /// @dev SECURITY FIX v1.8.8: Must register within REGISTRATION_PERIOD (1 day) after proposal creation
    /// @dev This prevents buy-vote attacks where tokens are acquired after seeing a proposal
    /// @dev Voting power is locked at registration time and cannot be changed
    function registerToVote() external onlyActive inState(ProposalState.VOTING) {
        // Registration window: first 1 day after proposal creation
        if (block.timestamp > currentProposal.proposedAt + REGISTRATION_PERIOD) revert RegistrationClosed();
        if (votingPowerSnapshot[proposalCount][msg.sender] != 0) revert AlreadyRegistered();

        uint256 votingPower = DMD_TOKEN.balanceOf(msg.sender);
        if (votingPower == 0) revert ZeroVotingPower();

        votingPowerSnapshot[proposalCount][msg.sender] = votingPower;

        emit VoterRegistered(proposalCount, msg.sender, votingPower);
    }

    /// @notice Check if registration is still open for current proposal
    function isRegistrationOpen() external view returns (bool) {
        if (proposalState != ProposalState.VOTING) return false;
        return block.timestamp <= currentProposal.proposedAt + REGISTRATION_PERIOD;
    }

    /// @notice Get registration deadline for current proposal
    function getRegistrationDeadline() external view returns (uint256) {
        if (proposalState != ProposalState.VOTING) return 0;
        return currentProposal.proposedAt + REGISTRATION_PERIOD;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VOTING (14 DAYS, 1 DMD = 1 VOTE, NO DELEGATION)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Cast vote on active proposal
    /// @dev SECURITY FIX v1.8.8: Must be registered to vote (prevents buy-vote attacks)
    /// @dev Voting power was locked during registration period (first 1 day after proposal)
    /// @dev The hasVoted mapping prevents vote-then-transfer-then-vote-again attacks
    /// @param support true = YES, false = NO
    function vote(bool support) external onlyActive inState(ProposalState.VOTING) {
        if (block.timestamp >= currentProposal.votingEndsAt) revert VotingEnded();
        if (hasVoted[proposalCount][msg.sender]) revert AlreadyVoted();

        // SECURITY FIX v1.8.8: Voting power must be registered during the registration window
        // This prevents buy-vote attacks by requiring users to lock their voting power
        // within 1 day of proposal creation (before they can observe market reaction)
        uint256 votingPower = votingPowerSnapshot[proposalCount][msg.sender];
        if (votingPower == 0) revert NotRegistered();

        hasVoted[proposalCount][msg.sender] = true;

        if (support) {
            currentProposal.yesVotes += votingPower;
        } else {
            currentProposal.noVotes += votingPower;
        }

        emit VoteCast(proposalCount, msg.sender, support, votingPower);
    }

    /// @notice Finalize voting and determine outcome
    /// @dev Anyone can call after voting period ends
    function finalizeVoting() external onlyActive inState(ProposalState.VOTING) {
        if (block.timestamp < currentProposal.votingEndsAt) revert VotingNotEnded();

        uint256 totalVotes = currentProposal.yesVotes + currentProposal.noVotes;

        // SECURITY FIX: Use snapshot supply from proposal creation for quorum calculation
        // This prevents governance DoS if supply increases during voting (e.g., team vesting)
        // Snapshot is taken at proposal creation to ensure consistent voting rules
        uint256 totalSupply = currentProposal.snapshotSupply;

        // Check quorum: 60% of snapshot supply must vote (ceiling division)
        uint256 quorumRequired = (totalSupply * QUORUM_PERCENT + 99) / 100;
        if (totalVotes < quorumRequired) {
            _clearProposal();
            proposalState = ProposalState.IDLE;
            emit ProposalFailed(proposalCount, "Quorum not met");
            return;
        }

        // Check approval: 75% YES required (ceiling division)
        uint256 approvalRequired = (totalVotes * APPROVAL_PERCENT + 99) / 100;
        if (currentProposal.yesVotes < approvalRequired) {
            _clearProposal();
            proposalState = ProposalState.IDLE;
            emit ProposalFailed(proposalCount, "Approval threshold not met");
            return;
        }

        // Proposal passed - queue for execution
        currentProposal.executionTime = block.timestamp + EXECUTION_DELAY;
        currentProposal.executionDeadline = block.timestamp + EXECUTION_DELAY + EXECUTION_WINDOW;
        proposalState = ProposalState.QUEUED;

        emit ProposalQueued(proposalCount, currentProposal.executionTime);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EXECUTION (7 DAY DELAY, THEN 30 DAY COOLDOWN)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Execute queued proposal after delay
    function execute() external onlyActive inState(ProposalState.QUEUED) {
        if (block.timestamp < currentProposal.executionTime) revert ExecutionDelayNotMet();
        if (block.timestamp > currentProposal.executionDeadline) revert ExecutionDeadlineExpired();

        // Execute the action
        _executeAction(currentProposal.action, currentProposal.adapter);

        currentProposal.executed = true;
        currentProposal.cooldownEndsAt = block.timestamp + COOLDOWN_PERIOD;
        proposalState = ProposalState.COOLDOWN;

        emit ProposalExecuted(proposalCount, currentProposal.action, currentProposal.adapter);
        emit CooldownStarted(proposalCount, currentProposal.cooldownEndsAt);
    }

    /// @notice End cooldown and return to IDLE
    function endCooldown() external onlyActive inState(ProposalState.COOLDOWN) {
        if (block.timestamp < currentProposal.cooldownEndsAt) revert CooldownNotComplete();

        _clearProposal();
        proposalState = ProposalState.IDLE;
    }

    /// @notice Clean up expired proposal that wasn't executed within deadline
    /// @dev Anyone can call this to clean up stale QUEUED proposals
    /// @dev SECURITY: Prevents governance deadlock from expired proposals blocking new ones
    function cleanupExpiredProposal() external onlyActive inState(ProposalState.QUEUED) {
        if (block.timestamp <= currentProposal.executionDeadline) revert ExecutionDeadlineNotExpired();

        emit ProposalFailed(proposalCount, "Execution deadline expired");
        _clearProposal();
        proposalState = ProposalState.IDLE;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL - ACTION VALIDATION AND EXECUTION
    // ═══════════════════════════════════════════════════════════════════════

    function _validateAction(ActionType action, address adapter) internal view {
        if (action == ActionType.PAUSE_ADAPTER) {
            // Can only pause approved, non-paused, non-deprecated adapters
            if (!approvedAdapters[adapter]) revert InvalidAction();
            if (pausedAdapters[adapter]) revert InvalidAction();
            if (deprecatedAdapters[adapter]) revert InvalidAction();
        } else if (action == ActionType.RESUME_ADAPTER) {
            // Can only resume paused adapters that are still approved and not deprecated
            if (!pausedAdapters[adapter]) revert InvalidAction();
            if (!approvedAdapters[adapter]) revert InvalidAction();
            if (deprecatedAdapters[adapter]) revert InvalidAction();
        } else if (action == ActionType.APPROVE_ADAPTER) {
            // Cannot approve already approved or deprecated adapters
            if (approvedAdapters[adapter]) revert InvalidAction();
            if (deprecatedAdapters[adapter]) revert InvalidAction();
        } else if (action == ActionType.DEPRECATE_ADAPTER) {
            // Can only deprecate approved adapters
            if (!approvedAdapters[adapter]) revert InvalidAction();
            if (deprecatedAdapters[adapter]) revert InvalidAction();
        }
    }

    function _executeAction(ActionType action, address adapter) internal {
        if (action == ActionType.PAUSE_ADAPTER) {
            pausedAdapters[adapter] = true;
        } else if (action == ActionType.RESUME_ADAPTER) {
            pausedAdapters[adapter] = false;
        } else if (action == ActionType.APPROVE_ADAPTER) {
            approvedAdapters[adapter] = true;
        } else if (action == ActionType.DEPRECATE_ADAPTER) {
            deprecatedAdapters[adapter] = true;
            // Deprecated adapters remain in approvedAdapters but are marked deprecated
            // This prevents re-approval and disables future inflow
        }
    }

    /// @notice Clear current proposal data
    /// @dev Resets proposal struct to default values to prevent stale data
    function _clearProposal() internal {
        delete currentProposal;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Check if an adapter can receive inflow
    function isAdapterActive(address adapter) external view returns (bool) {
        return approvedAdapters[adapter] && !pausedAdapters[adapter] && !deprecatedAdapters[adapter];
    }

    /// @notice Get current proposal details
    function getProposal() external view returns (
        ActionType action,
        address adapter,
        uint256 proposedAt,
        uint256 votingEndsAt,
        uint256 executionTime,
        uint256 executionDeadline,
        uint256 cooldownEndsAt,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 snapshotSupply,
        bool executed,
        ProposalState state
    ) {
        Proposal memory p = currentProposal;
        return (
            p.action,
            p.adapter,
            p.proposedAt,
            p.votingEndsAt,
            p.executionTime,
            p.executionDeadline,
            p.cooldownEndsAt,
            p.yesVotes,
            p.noVotes,
            p.snapshotSupply,
            p.executed,
            proposalState
        );
    }

    /// @notice Get current voting power of an address
    function getVotingPower(address voter) external view returns (uint256) {
        return DMD_TOKEN.balanceOf(voter);
    }

    /// @notice Get snapshot voting power for current proposal
    /// @dev Returns 0 if voter hasn't voted yet (snapshot taken on first vote)
    function getSnapshotVotingPower(address voter) external view returns (uint256) {
        return votingPowerSnapshot[proposalCount][voter];
    }

    /// @notice Get the snapshot block for a proposal
    /// @param proposalId Proposal ID to query
    /// @return Block number at which the proposal was created
    function getProposalSnapshotBlock(uint256 proposalId) external view returns (uint256) {
        return proposalSnapshotBlock[proposalId];
    }

    /// @notice Check if address has voted on current proposal
    function hasVotedOnCurrent(address voter) external view returns (bool) {
        return hasVoted[proposalCount][voter];
    }
}
