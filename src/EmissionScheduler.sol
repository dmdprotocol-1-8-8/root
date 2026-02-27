// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title EmissionScheduler - Year-based DMD emissions with 25% annual decay
/// @dev Fully immutable. EMISSION_CAP = 80% of 18M max supply = 14.4M
/// @notice Hard-coded emission schedule. No admin. No governance. No changes.
contract EmissionScheduler {
    error Unauthorized();

    // HARD-CODED ANNUAL EMISSION CAPS (IMMUTABLE)
    // Year 1: 3,600,000 DMD (max per year)
    // Year 2: 2,700,000 DMD (x0.75)
    // Year 3: 2,025,000 DMD
    // Year 4: 1,518,750 DMD
    // Year 5: 1,139,063 DMD
    // Year 6:   854,297 DMD
    // Year 7:   640,723 DMD
    // Year 8+:  Continue x0.75 decay until EMISSION_CAP reached
    uint256 public constant YEAR_1_EMISSION = 3_600_000e18;
    uint256 public constant DECAY_NUMERATOR = 75;
    uint256 public constant DECAY_DENOMINATOR = 100;
    // EMISSION_CAP = 80% of 18M max supply = 14.4M (for tBTC lockers via adapters)
    uint256 public constant EMISSION_CAP = 14_400_000e18;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    address public immutable MINT_DISTRIBUTOR;
    uint256 public immutable EMISSION_START_TIME;
    uint256 public totalEmitted;

    event EmissionClaimed(uint256 amount, uint256 year);

    constructor(address _mintDistributor) {
        if (_mintDistributor == address(0)) revert Unauthorized();
        MINT_DISTRIBUTOR = _mintDistributor;
        EMISSION_START_TIME = block.timestamp;
    }

    function claimEmission() external returns (uint256 amount) {
        if (msg.sender != MINT_DISTRIBUTOR) revert Unauthorized();

        amount = _claimableNow();
        if (amount == 0) return 0;

        totalEmitted += amount;
        emit EmissionClaimed(amount, _getCurrentYear());
    }

    function claimableNow() external view returns (uint256) { return _claimableNow(); }
    function getCurrentYear() external view returns (uint256) { return _getCurrentYear(); }
    function capReached() public view returns (bool) { return totalEmitted >= EMISSION_CAP; }

    /// @notice Get emission amount for a specific year
    /// @dev Uses iterative decay calculation - safe from overflow
    /// @param year Year number (0-indexed, year 0 = first year)
    /// @return Emission amount for that year
    function getYearEmission(uint256 year) public pure returns (uint256) {
        // SECURITY: Cap at 100 years - after that emissions are negligible
        // At year 100, emission would be ~0.000000000003% of original
        if (year >= 100) return 0;

        uint256 emission = YEAR_1_EMISSION;
        for (uint256 i = 0; i < year;) {
            emission = (emission * DECAY_NUMERATOR) / DECAY_DENOMINATOR;
            // Early exit optimization: if emission rounds to 0, no point continuing
            if (emission == 0) return 0;
            unchecked { ++i; }
        }
        return emission;
    }

    function currentEmissionRate() external view returns (uint256) {
        return getYearEmission(_getCurrentYear()) / SECONDS_PER_YEAR;
    }

    function _claimableNow() internal view returns (uint256) {
        if (capReached()) return 0;

        uint256 theoretical = _calculateTotalEmittedUpToNow();
        uint256 claimable = theoretical > totalEmitted ? theoretical - totalEmitted : 0;

        if (totalEmitted + claimable > EMISSION_CAP) {
            claimable = EMISSION_CAP - totalEmitted;
        }
        return claimable;
    }

    function _getCurrentYear() internal view returns (uint256) {
        return (block.timestamp - EMISSION_START_TIME) / SECONDS_PER_YEAR;
    }

    function _calculateTotalEmittedUpToNow() internal view returns (uint256) {
        uint256 elapsed = block.timestamp - EMISSION_START_TIME;
        uint256 totalEmission = 0;
        uint256 currentYear = 0;
        uint256 remainingTime = elapsed;

        // SECURITY: Cap iteration at 100 years to prevent DoS (emissions are 0 after year 100 anyway)
        while (remainingTime >= SECONDS_PER_YEAR && currentYear < 100) {
            totalEmission += getYearEmission(currentYear);
            remainingTime -= SECONDS_PER_YEAR;
            currentYear++;
            // Don't return early - continue to calculate partial year to avoid emission loss
        }

        if (remainingTime > 0 && currentYear < 100) {
            totalEmission += (getYearEmission(currentYear) * remainingTime) / SECONDS_PER_YEAR;
        }

        return totalEmission > EMISSION_CAP ? EMISSION_CAP : totalEmission;
    }
}
