// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IDMDToken} from "./interfaces/IDMDToken.sol";
import {IBTCReserveVault} from "./interfaces/IBTCReserveVault.sol";
import {IEmissionScheduler} from "./interfaces/IEmissionScheduler.sol";

/// @title MintDistributor
/// @notice Epoch-based DMD distribution proportional to tBTC lock weight
contract MintDistributor {

    error NoWeight();
    error NoEmissionsAvailable();
    error InvalidEpoch();
    error InvalidAddress();
    error SlippageExceeded();
    error ReentrancyGuard();
    error Unauthorized();
    error CacheStaleForLargeUserCount();

    uint256 public constant EPOCH_DURATION = 7 days;
    uint256 public constant MAX_USERS_DIRECT_CALC = 500;

    IDMDToken public immutable DMD_TOKEN;
    IBTCReserveVault public immutable VAULT;
    IEmissionScheduler public immutable SCHEDULER;
    uint256 public immutable DISTRIBUTION_START_TIME;

    struct EpochData {
        uint256 totalEmission;
        uint256 snapshotWeight;
        bool finalized;
        uint256 totalMinted;
        uint256 finalizationTime;
    }

    uint256 private _locked = 1;
    uint256 public nextEpochToFinalize;
    mapping(uint256 => EpochData) public epochs;
    mapping(uint256 => mapping(address => bool)) public claimed;
    mapping(address => mapping(uint256 => uint256)) public positionDmdMinted;

    event EpochFinalized(uint256 indexed epochId, uint256 totalEmission, uint256 snapshotWeight, uint256 finalizationTime);
    event Claimed(address indexed user, uint256 indexed epochId, uint256 amount);
    event PositionDmdMintedCleared(address indexed user, uint256 indexed positionId);
    event RewardCapped(address indexed user, uint256 indexed epochId, uint256 calculatedShare, uint256 cappedShare);

    modifier nonReentrant() {
        if (_locked == 2) revert ReentrancyGuard();
        _locked = 2;
        _;
        _locked = 1;
    }

    constructor(IDMDToken _dmdToken, IBTCReserveVault _vault, IEmissionScheduler _scheduler) {
        if (address(_dmdToken) == address(0) || address(_vault) == address(0) || address(_scheduler) == address(0)) {
            revert InvalidAddress();
        }
        DMD_TOKEN = _dmdToken;
        VAULT = _vault;
        SCHEDULER = _scheduler;
        DISTRIBUTION_START_TIME = block.timestamp;
    }

    function finalizeEpoch() external nonReentrant {
        uint256 currentEpoch = getCurrentEpoch();
        if (currentEpoch == 0) revert InvalidEpoch();
        if (nextEpochToFinalize >= currentEpoch) revert InvalidEpoch();

        uint256 epochToFinalize = nextEpochToFinalize;
        uint256 vestedWeight = _getVestedWeightForFinalization(epochToFinalize);
        if (vestedWeight == 0) {
            nextEpochToFinalize = epochToFinalize + 1;
            return;
        }

        uint256 emission = SCHEDULER.claimEmission();
        if (emission == 0) revert NoEmissionsAvailable();

        epochs[epochToFinalize] = EpochData({
            totalEmission: emission,
            snapshotWeight: vestedWeight,
            finalized: true,
            totalMinted: 0,
            finalizationTime: block.timestamp
        });
        nextEpochToFinalize = epochToFinalize + 1;

        emit EpochFinalized(epochToFinalize, emission, vestedWeight, block.timestamp);
    }

    function finalizeMultipleEpochs(uint256 count) external nonReentrant {
        uint256 currentEpoch = getCurrentEpoch();
        for (uint256 i = 0; i < count;) {
            if (nextEpochToFinalize >= currentEpoch) break;

            uint256 vestedWeight = _getVestedWeightForFinalization(nextEpochToFinalize);
            if (vestedWeight == 0) {
                nextEpochToFinalize++;
                unchecked { ++i; }
                continue;
            }

            uint256 emission = SCHEDULER.claimEmission();
            if (emission == 0) break;

            epochs[nextEpochToFinalize] = EpochData({
                totalEmission: emission,
                snapshotWeight: vestedWeight,
                finalized: true,
                totalMinted: 0,
                finalizationTime: block.timestamp
            });

            emit EpochFinalized(nextEpochToFinalize, emission, vestedWeight, block.timestamp);
            nextEpochToFinalize++;
            unchecked { ++i; }
        }
    }

    function claim(uint256 epochId) external nonReentrant {
        _claim(epochId, 0);
    }

    function claimWithSlippage(uint256 epochId, uint256 minAmount) external nonReentrant {
        _claim(epochId, minAmount);
    }

    function claimMultiple(uint256[] calldata epochIds) external nonReentrant {
        uint256 len = epochIds.length;
        for (uint256 i = 0; i < len;) {
            _claimInternal(epochIds[i], 0);
            unchecked { ++i; }
        }
    }

    function claimMultipleWithSlippage(uint256[] calldata epochIds, uint256[] calldata minAmounts) external nonReentrant {
        uint256 len = epochIds.length;
        for (uint256 i = 0; i < len;) {
            uint256 minAmount = i < minAmounts.length ? minAmounts[i] : 0;
            _claimInternal(epochIds[i], minAmount);
            unchecked { ++i; }
        }
    }

    function claimAll() external nonReentrant {
        uint256 nextToFinalize = nextEpochToFinalize;
        for (uint256 epochId = 0; epochId < nextToFinalize;) {
            _claimInternal(epochId, 0);
            unchecked { ++epochId; }
        }
    }

    // --- View Functions ---

    function getCurrentEpoch() public view returns (uint256) {
        return (block.timestamp - DISTRIBUTION_START_TIME) / EPOCH_DURATION;
    }

    function getPendingEpochCount() external view returns (uint256) {
        uint256 current = getCurrentEpoch();
        return current > nextEpochToFinalize ? current - nextEpochToFinalize : 0;
    }

    function getClaimableAmount(address user, uint256 epochId) external view returns (uint256) {
        EpochData storage epoch = epochs[epochId];
        if (!epoch.finalized || claimed[epochId][user] || epoch.snapshotWeight == 0) return 0;

        uint256 userWeight = _getUserEligibleWeight(user, epoch.finalizationTime);
        if (userWeight == 0) return 0;

        uint256 share = (epoch.totalEmission * userWeight) / epoch.snapshotWeight;
        uint256 remaining = epoch.totalEmission > epoch.totalMinted ?
            epoch.totalEmission - epoch.totalMinted : 0;

        return share > remaining ? remaining : share;
    }

    function getTotalClaimable(address user) external view returns (uint256) {
        uint256 total = 0;
        uint256 nextToFinalize = nextEpochToFinalize;

        for (uint256 epochId = 0; epochId < nextToFinalize;) {
            EpochData storage epoch = epochs[epochId];
            if (epoch.finalized && !claimed[epochId][user] && epoch.snapshotWeight > 0) {
                uint256 userWeight = _getUserEligibleWeight(user, epoch.finalizationTime);
                if (userWeight > 0) {
                    uint256 share = (epoch.totalEmission * userWeight) / epoch.snapshotWeight;
                    uint256 remaining = epoch.totalEmission > epoch.totalMinted ?
                        epoch.totalEmission - epoch.totalMinted : 0;
                    total += share > remaining ? remaining : share;
                }
            }
            unchecked { ++epochId; }
        }
        return total;
    }

    function getClaimableEpochCount(address user) external view returns (uint256) {
        uint256 count = 0;
        uint256 nextToFinalize = nextEpochToFinalize;

        for (uint256 epochId = 0; epochId < nextToFinalize;) {
            EpochData storage epoch = epochs[epochId];
            if (epoch.finalized && !claimed[epochId][user] && epoch.snapshotWeight > 0) {
                uint256 userWeight = _getUserEligibleWeight(user, epoch.finalizationTime);
                if (userWeight > 0) {
                    count++;
                }
            }
            unchecked { ++epochId; }
        }
        return count;
    }

    function hasClaimed(address user, uint256 epochId) external view returns (bool) {
        return claimed[epochId][user];
    }

    function isEligibleForEpoch(address user, uint256 epochId) external view returns (bool) {
        EpochData storage epoch = epochs[epochId];
        if (!epoch.finalized) return false;
        return _getUserEligibleWeight(user, epoch.finalizationTime) > 0;
    }

    function getEpochData(uint256 epochId) external view returns (uint256 totalEmission, uint256 snapshotWeight, bool finalized) {
        EpochData storage e = epochs[epochId];
        return (e.totalEmission, e.snapshotWeight, e.finalized);
    }

    function getEpochDataExtended(uint256 epochId) external view returns (
        uint256 totalEmission,
        uint256 snapshotWeight,
        bool finalized,
        uint256 totalMinted,
        uint256 finalizationTime
    ) {
        EpochData storage e = epochs[epochId];
        return (e.totalEmission, e.snapshotWeight, e.finalized, e.totalMinted, e.finalizationTime);
    }

    function timeUntilNextEpoch() external view returns (uint256) {
        uint256 nextStart = DISTRIBUTION_START_TIME + ((getCurrentEpoch() + 1) * EPOCH_DURATION);
        return block.timestamp >= nextStart ? 0 : nextStart - block.timestamp;
    }

    function getPositionDmdMinted(address user, uint256 positionId) external view returns (uint256) {
        return positionDmdMinted[user][positionId];
    }

    function clearPositionDmdMinted(address user, uint256 positionId) external {
        if (msg.sender != address(VAULT)) revert Unauthorized();
        delete positionDmdMinted[user][positionId];
        emit PositionDmdMintedCleared(user, positionId);
    }

    // --- Internal ---

    function _claim(uint256 epochId, uint256 minAmount) internal {
        uint256 amount = _claimInternal(epochId, minAmount);
        if (amount == 0) revert NoWeight();
    }

    function _claimInternal(uint256 epochId, uint256 minAmount) internal returns (uint256) {
        EpochData storage epoch = epochs[epochId];
        if (!epoch.finalized) return 0;
        if (claimed[epochId][msg.sender]) return 0;
        if (epoch.snapshotWeight == 0) return 0;

        // Only count weight from positions that existed before finalization
        uint256 userWeight = _getUserEligibleWeight(msg.sender, epoch.finalizationTime);
        if (userWeight == 0) return 0;

        uint256 share = (epoch.totalEmission * userWeight) / epoch.snapshotWeight;
        uint256 calculatedShare = share;

        uint256 remaining = epoch.totalEmission > epoch.totalMinted ?
            epoch.totalEmission - epoch.totalMinted : 0;

        if (share > remaining) {
            share = remaining;
            emit RewardCapped(msg.sender, epochId, calculatedShare, share);
        }

        if (share == 0) return 0;
        if (minAmount > 0 && share < minAmount) revert SlippageExceeded();

        claimed[epochId][msg.sender] = true;
        epoch.totalMinted += share;

        DMD_TOKEN.mint(msg.sender, share);
        _distributeToPositions(msg.sender, share, epoch.finalizationTime);

        emit Claimed(msg.sender, epochId, share);
        return share;
    }

    /// @dev Only count positions locked before the cutoff time
    function _getUserEligibleWeight(address user, uint256 cutoffTime) internal view returns (uint256) {
        uint256[] memory positions = VAULT.getActivePositions(user);
        uint256 total = 0;

        for (uint256 i = 0; i < positions.length;) {
            uint256 posId = positions[i];
            if (VAULT.getPositionLockTime(user, posId) < cutoffTime) {
                total += VAULT.getPositionVestedWeight(user, posId);
            }
            unchecked { ++i; }
        }
        return total;
    }

    /// @dev Distribute DMD across eligible positions proportionally
    function _distributeToPositions(address user, uint256 totalDmd, uint256 cutoffTime) internal {
        if (totalDmd == 0) return;

        uint256[] memory positions = VAULT.getActivePositions(user);
        uint256 len = positions.length;
        if (len == 0) return;

        uint256 totalWeight = 0;
        uint256[] memory weights = new uint256[](len);
        bool[] memory eligible = new bool[](len);

        for (uint256 i = 0; i < len;) {
            uint256 positionId = positions[i];
            uint256 lockTime = VAULT.getPositionLockTime(user, positionId);

            if (lockTime < cutoffTime) {
                weights[i] = VAULT.getPositionVestedWeight(user, positionId);
                totalWeight += weights[i];
                eligible[i] = true;
            }
            unchecked { ++i; }
        }

        if (totalWeight == 0) return;

        uint256 distributed = 0;
        uint256 lastEligibleIdx = type(uint256).max;
        
        for (uint256 i = len; i > 0;) {
            unchecked { --i; }
            if (eligible[i]) {
                lastEligibleIdx = i;
                break;
            }
        }

        for (uint256 i = 0; i < len;) {
            if (eligible[i]) {
                uint256 posId = positions[i];
                uint256 posShare;

                if (i == lastEligibleIdx) {
                    posShare = totalDmd - distributed;
                } else {
                    posShare = (totalDmd * weights[i]) / totalWeight;
                }

                if (posShare > 0) {
                    positionDmdMinted[user][posId] += posShare;
                    distributed += posShare;
                }
            }
            unchecked { ++i; }
        }
    }

    /// @dev Get vested weight - requires fresh cache for large user counts
    function _getVestedWeightForFinalization(uint256) internal view returns (uint256) {
        uint256 cacheAge = block.timestamp - VAULT.lastWeightCacheUpdate();
        uint256 validity = VAULT.CACHE_VALIDITY_PERIOD();
        bool updating = VAULT.cacheUpdateInProgress();
        uint256 users = VAULT.getTotalUsers();

        // Fresh cache available - use it
        if (cacheAge < validity && !updating) {
            uint256 c = VAULT.cachedTotalVestedWeight();
            if (c > 0) return c;
        }

        // Small user count - compute directly
        if (users <= MAX_USERS_DIRECT_CALC) {
            try VAULT.getTotalVestedWeight() returns (uint256 w) {
                return w;
            } catch {}
        }

        // Large user count with stale cache - require cache update first
        // Using raw totalSystemWeight as fallback would over-distribute rewards
        // because raw weight includes non-vested positions (warmup period)
        revert CacheStaleForLargeUserCount();
    }
}
