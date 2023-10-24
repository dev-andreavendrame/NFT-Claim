// SPDX-License-Identifier: MIT
// Created by 3Tech Studio (mail dev.andreavendrame@gmail.com)
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract Erc1155Claimer is Pausable, AccessControl, IERC1155Receiver {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /**
     * -----------------------------------------------------
     * -------------------- NFTS DETAILS -------------------
     * -----------------------------------------------------
     */

    mapping(address => bool) public whitelistedWallets;

    // Counters for different claim event types
    uint256 private _simpleClaimCounter;
    uint256 private _randomClaimCounter;

    // Tracking of active claim events
    uint256[] private _simpleClaimEventsActive;
    uint256[] private _randomClaimEventsActive;

    mapping(uint256 => SimpleClaimEvent) public simpleClaimEventDetails;
    mapping(uint256 => RandomClaimEvent) public randomClaimEventDetails;

    // Claim Events entries permissions
    mapping(uint256 => mapping(address => uint256)) public simpleClaimableNfts; // SimpleClaimEvent.id => wallet address => claimable NFTs amount
    mapping(uint256 => mapping(address => uint256)) public randomClaimableNfts; // RandomClaimEvent.id => wallet address => claimable NFTs amount

    // Claim types
    enum ClaimType {
        SIMPLE,
        RANDOM
    }

    struct SimpleClaimEvent {
        uint256 id;
        bool isActive;
        address contractAddress;
        uint256 tokenId;
    }

    struct RandomClaimEvent {
        uint256 id;
        bool isActive;
        address contractAddress;
        uint256[] tokenIds;
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(PAUSER_ROLE, _msgSender());
        _grantRole(MANAGER_ROLE, _msgSender());
    }

    /**
     * --------------------------------------------------------------------
     * -------------------- CONTRACT MANAGEMENT FUNCTIONS -----------------
     * --------------------------------------------------------------------
     */

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * --------------------------------------------------------------------
     * -------------------- MANAGE WHITELISTED NFTS SENDERS ---------------
     * --------------------------------------------------------------------
     */

    /**
     * @dev Whitelist a specific address letting it be able to send NFTs to this contract
     *
     * @param newSender Address to add to the whitelist
     */
    function addWhitelistedAddress(address newSender)
        external
        onlyRole(MANAGER_ROLE)
    {
        require(newSender != address(0), "You must provide a valid address");

        // Add support
        whitelistedWallets[newSender] = true;
    }

    /**
     * @dev Remove the whitelist from specific address.
     * From now on this address will no longer be able to send NFTs to this contract.
     *
     * @param oldSender Address to remove from the whitelist
     */
    function removeWhitelistedAddress(address oldSender)
        external
        onlyRole(MANAGER_ROLE)
    {
        require(oldSender != address(0), "You must provide a valid address");

        // Remove support
        whitelistedWallets[oldSender] = false;
    }

    /**
     * --------------------------------------------------------------------
     * -------------------- MANAGE CLAIMING ENTRIES -----------------------
     * --------------------------------------------------------------------
     */

    /**
     * @dev Add the permission for a specified address to claim a specified
     * number of copies of a specified ERC1155 NFT
     *
     * @param simpleClaimEventId ID of the claim event
     * @param claimer address to let be able to claim in this event
     * @param claimableAmount NFT copies to let the user withdraw
     */
    function setSimpleClaimEntry(
        uint256 simpleClaimEventId,
        address claimer,
        uint256 claimableAmount
    ) external onlyRole(MANAGER_ROLE) {
        // Check if specified ID is still active
        SimpleClaimEvent memory eventDetails = simpleClaimEventDetails[
            simpleClaimEventId
        ];

        require(eventDetails.isActive, "This claim event is not active");
        // Check parameter validity
        require(claimableAmount > 0, "Can't let claim 0 NFT copies");

        simpleClaimableNfts[simpleClaimEventId][claimer] = claimableAmount;
    }

    /**
     * @dev Add in batch the permission for a specified array of addresses to
     * claim a specified number of copies of a specified ERC1155 NFT
     *
     * @param simpleClaimEventId ID of the claim event
     * @param claimers addresses to let be able to claim in this event
     * @param claimableAmounts NFT copies to let the users withdraw
     */
    function setBatchSimpleClaimEntries(
        uint256 simpleClaimEventId,
        address[] memory claimers,
        uint256[] memory claimableAmounts
    ) external onlyRole(MANAGER_ROLE) {
        // Check if specified ID is still active
        SimpleClaimEvent memory eventDetails = simpleClaimEventDetails[
            simpleClaimEventId
        ];
        require(eventDetails.isActive, "This claim event is not active");

        require(claimers.length > 0, "Can't have an empty claimers list");
        require(
            claimableAmounts.length == claimers.length,
            "Claimers and amounts don't have the same length"
        );

        for (uint256 i = 0; i < claimableAmounts.length; i++) {
            // Check parameter validity
            require(claimableAmounts[i] > 0, "Can't let claim 0 NFT copies");

            simpleClaimableNfts[simpleClaimEventId][
                claimers[i]
            ] = claimableAmounts[i];
        }
    }

    /**
     * @dev Add the permission for a specified address to claim a specified number of NFTs
     * from a specific NFT pool made by different NFTs that belong to the same ERC1155 contract
     *
     * @param randomClaimEventId ID of the claim event
     * @param newClaimer address to let be able to claim in this event
     * @param claimableAmount NFT copies to let the user withdraw
     */
    function setRandomClaimEntry(
        uint256 randomClaimEventId,
        address newClaimer,
        uint256 claimableAmount
    ) external onlyRole(MANAGER_ROLE) {
        // Check if specified ID is still active
        RandomClaimEvent memory eventDetails = randomClaimEventDetails[
            randomClaimEventId
        ];
        require(eventDetails.isActive, "This claim event is not active");
        // Check parameter validity
        require(claimableAmount > 0, "Can't let claim 0 NFT copies");

        // SimpleClaimEvent.id => wallet address => claimable NFTs amount
        randomClaimableNfts[randomClaimEventId][newClaimer] = claimableAmount;
    }

    /**
     * @dev Add in batch the permission for the specified addresses to claim a
     * specified number of NFTs from a specific NFT pool made by different NFTs
     * that belong to the same ERC1155 contract
     *
     * @param randomClaimEventId ID of the claim event
     * @param claimers addresses to let be able to claim in this event
     * @param claimableAmounts NFT copies to let the users withdraw
     */
    function setBatchRandomClaimEntries(
        uint256 randomClaimEventId,
        address[] memory claimers,
        uint256[] memory claimableAmounts
    ) external onlyRole(MANAGER_ROLE) {
        // Check if specified ID is still active
        RandomClaimEvent memory eventDetails = randomClaimEventDetails[
            randomClaimEventId
        ];
        require(eventDetails.isActive, "This claim event is not active");

        require(claimers.length > 0, "Can't have an empty claimers list");
        require(
            claimableAmounts.length == claimers.length,
            "Claimers and amounts don't have the same length"
        );

        for (uint256 i = 0; i < claimableAmounts.length; i++) {
            // Check parameter validity
            require(claimableAmounts[i] > 0, "Can't let claim 0 NFT copies");

            randomClaimableNfts[randomClaimEventId][
                claimers[i]
            ] = claimableAmounts[i];
        }
    }

    /**
     * @dev Disable a claim event so no wallet will be able to claim
     * other NFTs through it
     *
     * @param claimType one value in the ClaimType enum set
     * @param claimEventId ID of the event to disable
     */
    function disableClaimEvent(ClaimType claimType, uint256 claimEventId)
        external
        onlyRole(MANAGER_ROLE)
    {
        if (claimType == ClaimType.SIMPLE) {
            simpleClaimEventDetails[claimEventId].isActive = false;
            _removeSimpleClaimActiveEvent(claimEventId);
        } else if (claimType == ClaimType.RANDOM) {
            randomClaimEventDetails[claimEventId].isActive = false;
            _removeRandomClaimActiveEvent(claimEventId);
        } else {
            revert("No valid 'Claim type provided");
        }
    }

    /**
     * @dev Create a new Simple Claim event.
     * Through this event allowed addresses will be able to claim
     * multiple copies of a specific ERC1155 NFT.
     *
     * @param contractAddress address of the ERC1155 contract
     * @param tokenId ID of the token that will be claimed
     */
    function createSimpleClaimEvent(address contractAddress, uint256 tokenId)
        external
        onlyRole(MANAGER_ROLE)
    {
        uint256 currentEventId = _simpleClaimCounter;
        _simpleClaimCounter = _simpleClaimCounter + 1;

        SimpleClaimEvent memory newClaimEvent = SimpleClaimEvent(
            currentEventId,
            true,
            contractAddress,
            tokenId
        );
        // Add event details
        simpleClaimEventDetails[currentEventId] = newClaimEvent;
        // Add event to active list
        _simpleClaimEventsActive.push(currentEventId);
    }

    /**
     * @dev Create a new Random Claim event.
     * Through this event allowed addresses will be able to claim
     * multiple copies of a specific ERC1155 NFTs set.
     *
     * @param contractAddress address of the ERC1155 contract
     * @param tokenIds IDs of the token that will be claimed
     */
    function createRandomClaimEvent(
        address contractAddress,
        uint256[] memory tokenIds
    ) external onlyRole(MANAGER_ROLE) {
        uint256 currentEventId = _randomClaimCounter;
        _randomClaimCounter = _randomClaimCounter + 1;

        require(tokenIds.length > 0, "Can't create a claim set with 0 items");

        RandomClaimEvent memory newClaimEvent = RandomClaimEvent(
            currentEventId,
            true,
            contractAddress,
            tokenIds
        );
        // Add event details
        randomClaimEventDetails[currentEventId] = newClaimEvent;
        // Add event to active list
        _randomClaimEventsActive.push(currentEventId);
    }

    /**
     * --------------------------------------------------------------------
     * -------------------- CLAIM FUNCTIONS IMPLEMENTATIONS ---------------
     * --------------------------------------------------------------------
     */

    /**
     * @dev Let the transaction sender to claim the NFTs that he is allowed
     * to do related to a specific claim event
     *
     * @param claimType one value in the ClaimType enum set
     * @param claimId ID of the claim event
     *
     * @return the number of NFTs claimed
     */
    function claim(ClaimType claimType, uint256 claimId)
        public
        returns (uint256)
    {
        if (claimType == ClaimType.SIMPLE) {
            uint256 claimed = _simpleClaim(claimId, _msgSender());
            return claimed;
        } else if (claimType == ClaimType.RANDOM) {
            uint256 claimed = _randomClaim(claimId, _msgSender());
            return claimed;
        } else {
            revert("No valid Claim type speficied");
        }
    }

    /**
     * @dev claim NFTs through a simple claim event
     *
     * @param claimId ID of the Simple Claim event
     * @param claimer address of the claimer
     *
     * @return the amount of claimed NFTs
     */
    function _simpleClaim(uint256 claimId, address claimer)
        public
        returns (uint256)
    {
        SimpleClaimEvent memory eventDetails = simpleClaimEventDetails[claimId];

        require(eventDetails.isActive, "The claim event is ended");

        // Check if address is entitled to claim something
        uint256 nftsToClaim = simpleClaimableNfts[claimId][claimer];
        require(nftsToClaim > 0, "You don't have any NFT to claim");

        ERC1155 erc1155instance = ERC1155(eventDetails.contractAddress);
        uint256 contractNftsBalance = erc1155instance.balanceOf(
            address(this),
            eventDetails.tokenId
        );

        if (contractNftsBalance == 0) {
            revert("No NFTs in the smart contract to claim");
        }

        uint256 claimableNfts = 0;

        if (nftsToClaim > contractNftsBalance) {
            // Can't claim all the assigned NFTs
            claimableNfts = contractNftsBalance;
            simpleClaimableNfts[claimId][claimer] =
                nftsToClaim -
                contractNftsBalance;
        } else {
            claimableNfts = nftsToClaim;
            simpleClaimableNfts[claimId][claimer] = 0;
        }

        erc1155instance.safeTransferFrom(
            address(this),
            claimer,
            eventDetails.tokenId,
            claimableNfts,
            "0x00"
        );

        return claimableNfts;
    }

    /**
     * @dev claim NFTs through a random claim event
     *
     * @param claimId ID of the Simple Claim event
     * @param claimer address of the claimer
     *
     * @return the amount of claimed NFTs
     */
    function _randomClaim(uint256 claimId, address claimer)
        public
        returns (uint256)
    {
        RandomClaimEvent memory eventDetails = randomClaimEventDetails[claimId];
        uint256 uniqueIdsLength = eventDetails.tokenIds.length;

        require(eventDetails.isActive, "The claim event is ended");

        // Check if address is entitled to claim something
        uint256 nftsToClaim = randomClaimableNfts[claimId][claimer];
        require(nftsToClaim > 0, "You don't have any NFT to claim");

        ERC1155 erc1155instance = ERC1155(eventDetails.contractAddress);

        uint256[] memory availableAmounts = new uint256[](uniqueIdsLength);

        // Check balances of the NFTs by ID
        for (uint256 i = 0; i < uniqueIdsLength; i++) {
            availableAmounts[i] = erc1155instance.balanceOf(
                address(this),
                eventDetails.tokenIds[i]
            );
        }

        // Calculate the distribution of the claimable NFTs
        uint256[] memory claimableDistribution = _getDistributionValues(
            availableAmounts,
            nftsToClaim
        );

        require(
            claimableDistribution.length == uniqueIdsLength,
            "Error getting NFTs distribution"
        );

        // Calculate how many NFTs will be distributed
        uint256 claimedNfts = 0;
        for (uint256 i = 0; i < claimableDistribution.length; i++) {
            claimedNfts = claimedNfts + claimableDistribution[i];
        }

        require(
            claimedNfts <= nftsToClaim,
            "Error defining the distribution of the NFTs to claim"
        );

        // Update claimable NFTs to prevent reentrancy attack
        randomClaimableNfts[claimId][claimer] = nftsToClaim - claimedNfts;

        // Claim the Nfts
        erc1155instance.safeBatchTransferFrom(
            address(this),
            claimer,
            eventDetails.tokenIds,
            claimableDistribution,
            "0x00"
        );

        return claimedNfts;
    }

    /**
     * --------------------------------------------------------------------
     * -------------------- RANDOM GENERATION FUNCTION --------------------
     * --------------------------------------------------------------------
     */

    /**
     * @dev This function calculate the amounts of NFTs to claim given a specific
     * distribution set.
     *
     * @param availableAmounts amounts of copies of each NFT in claimable set.
     * The length of the array is a assumed to be greater of equal to 1.
     * @param amountToClaim total NFTs copies to select in the 'availableAmounts' set.
     * It is assumed to be greater of equal to 1.
     *
     * @return An array representing the distributed NFT amounts.
     * The length of the result is the same of the 'availableAmounts' parameter and
     * where the result array values, result[i] are values between in the range [0, availableAmounts[i]]
     * If 'amountToClaim' is > than the sum of the 'availableAmounts' array values the result will
     * be the 'availableAmounts' paraters itself.
     *
     * Note the sum of the available amounts can be lower than the parameter 'amountToClaim'.
     * We can have values in the 'availableAmounts' array equal to 0.
     * We know that the result distrubution is not a fair distribution,
     * but it's fine as it is calculated here for our aims.
     */
    function _getDistributionValues(
        uint256[] memory availableAmounts,
        uint256 amountToClaim
    ) public view returns (uint256[] memory) {
        uint256[] memory nftsToClaim;
        uint256[] memory currentAvailableAmounts = availableAmounts;
        uint256 nftsLeft = amountToClaim; // Nfts left to distribute

        (nftsToClaim, nftsLeft, currentAvailableAmounts) = _getRandomValues(
            availableAmounts,
            amountToClaim
        );

        (nftsToClaim, nftsLeft, currentAvailableAmounts) = _averageDistribution(
            nftsToClaim,
            nftsLeft,
            currentAvailableAmounts
        );

        (nftsToClaim, nftsLeft, currentAvailableAmounts) = _finalDistribution(
            nftsToClaim,
            nftsLeft,
            currentAvailableAmounts
        );

        return nftsToClaim;
    }

    function _getRandomValues(
        uint256[] memory availableAmounts,
        uint256 amountToClaim
    )
        private
        view
        returns (
            uint256[] memory,
            uint256,
            uint256[] memory
        )
    {
        uint256[] memory nftsToClaim = new uint256[](availableAmounts.length);
        uint256[] memory currentAvailableAmounts = availableAmounts;
        uint256 nftsLeft = amountToClaim;

        // Calculate the initial seed
        uint256 seed = uint256(
            keccak256(abi.encodePacked(block.timestamp, msg.sender, gasleft()))
        );

        // Initialization
        for (uint256 i = 0; i < availableAmounts.length; i++) {
            nftsToClaim[i] = 0;
        }

        // Calculate starting point to choose the first NFT in the available amounts
        uint256 index = seed % availableAmounts.length;
        // Initial value to get a random amount
        uint256 maxRandom = 0;
        if (amountToClaim < availableAmounts.length) {
            maxRandom = 1;
        } else {
            maxRandom = amountToClaim / availableAmounts.length + 1;
        }

        for (uint256 i = 0; i < availableAmounts.length; i++) {
            // Reset index if max length reached
            index = index % availableAmounts.length;

            require(index < 5 && index >= 0, "Problemi con l'indice");

            // Operations
            uint256 randomNumber = (seed % maxRandom) + 1;
            uint256 nftsToAssign = 0;
            if (nftsLeft >= randomNumber) {
                nftsToAssign = randomNumber;
                if (nftsToAssign <= availableAmounts[index]) {
                    // Enough NFTs to distribute of this type
                    nftsToClaim[index] = nftsToAssign;
                    availableAmounts[index] =
                        availableAmounts[index] -
                        nftsToAssign;
                    nftsLeft = nftsLeft - nftsToAssign;
                } else {
                    nftsToClaim[index] = availableAmounts[index];
                    nftsLeft = nftsLeft - availableAmounts[index];
                    availableAmounts[index] = 0;
                }
            } else {
                if (nftsLeft <= availableAmounts[index]) {
                    nftsToClaim[index] = nftsLeft;
                    availableAmounts[index] =
                        availableAmounts[index] -
                        nftsLeft;
                    return (nftsToClaim, 0, availableAmounts);
                } else {
                    nftsToClaim[i] = availableAmounts[index];
                    nftsLeft = nftsLeft - availableAmounts[index];
                    availableAmounts[index] = 0;
                }
            }

            // Recalculate seed & index
            seed = uint256(keccak256(abi.encodePacked(seed, gasleft())));
            index = index + 1;
        }

        uint256 totalClaimable = 0;
        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < availableAmounts.length; i++) {
            totalClaimable = totalClaimable + availableAmounts[i];
            totalClaimed = totalClaimed + nftsToClaim[i];
        }

        require(
            nftsLeft + totalClaimed == amountToClaim,
            "Error with distributing random NFTs, try again"
        );

        return (nftsToClaim, nftsLeft, currentAvailableAmounts);
    }

    function _averageDistribution(
        uint256[] memory currentDistribution,
        uint256 amountToClaim,
        uint256[] memory availableAmounts
    )
        private
        view
        returns (
            uint256[] memory,
            uint256,
            uint256[] memory
        )
    {
        // Calculate an average-like value to use in the next distribution steps
        uint256 fakeAverage = 0;
        uint256[] memory nftsToClaim = currentDistribution;
        uint256[] memory currentAvailableAmounts = availableAmounts;
        uint256 nftsLeft = amountToClaim;

        uint256 initialAvailableAmount = 0;
        uint256 initialDistributedAmount = 0;

        for (uint256 i = 0; i < currentAvailableAmounts.length; i++) {
            initialAvailableAmount =
                initialAvailableAmount +
                availableAmounts[i];
            initialDistributedAmount =
                initialDistributedAmount +
                currentDistribution[i];
        }

        for (uint256 i = 0; i < currentAvailableAmounts.length; i++) {
            fakeAverage = fakeAverage + currentAvailableAmounts[i];
        }

        fakeAverage = fakeAverage / currentAvailableAmounts.length + 1;

        for (uint256 i = 0; i < currentAvailableAmounts.length; i++) {
            if (nftsLeft >= fakeAverage) {
                if (fakeAverage >= currentAvailableAmounts[i]) {
                    nftsToClaim[i] =
                        nftsToClaim[i] +
                        currentAvailableAmounts[i];
                    nftsLeft = nftsLeft - currentAvailableAmounts[i];
                    currentAvailableAmounts[i] = 0;
                } else {
                    nftsToClaim[i] = nftsToClaim[i] + fakeAverage;
                    currentAvailableAmounts[i] =
                        currentAvailableAmounts[i] -
                        fakeAverage;
                    nftsLeft = nftsLeft - fakeAverage;
                }
            } else {
                if (nftsLeft >= currentAvailableAmounts[i]) {
                    nftsToClaim[i] =
                        nftsToClaim[i] +
                        currentAvailableAmounts[i];
                    nftsLeft = nftsLeft - currentAvailableAmounts[i];
                    currentAvailableAmounts[i] = 0;
                } else {
                    nftsToClaim[i] = nftsToClaim[i] + nftsLeft;
                    nftsLeft = 0;
                    return (nftsToClaim, nftsLeft, currentAvailableAmounts);
                }
            }
        }

        // Debug
        uint256 finalAvailableAmount = 0;
        uint256 finalDistributedAmount = 0;
        for (uint256 i = 0; i < currentAvailableAmounts.length; i++) {
            finalDistributedAmount = finalDistributedAmount + nftsToClaim[i];
            finalAvailableAmount =
                finalAvailableAmount +
                currentAvailableAmounts[i];
        }

        require(
            initialDistributedAmount + amountToClaim ==
                nftsLeft + finalDistributedAmount,
            "Wrong distribution"
        );

        return (nftsToClaim, nftsLeft, currentAvailableAmounts);
    }

    function _finalDistribution(
        uint256[] memory currentDistribution,
        uint256 amountToClaim,
        uint256[] memory currentAvailableAmounts
    )
        private
        view
        returns (
            uint256[] memory,
            uint256,
            uint256[] memory
        )
    {
        uint256[] memory nftsToClaim = currentDistribution;
        uint256[] memory remainingAvailableNfts = currentAvailableAmounts;
        uint256 nftsLeft = amountToClaim;
        // Final step (distribution of the remaining NFTs)
        if (nftsLeft > 0) {
            for (uint256 i = 0; i < remainingAvailableNfts.length; i++) {
                if (remainingAvailableNfts[i] >= nftsLeft) {
                    nftsToClaim[i] = nftsToClaim[i] + nftsLeft;
                    remainingAvailableNfts[i] =
                        remainingAvailableNfts[i] -
                        nftsLeft;
                    return (nftsToClaim, 0, remainingAvailableNfts);
                } else {
                    nftsToClaim[i] = nftsToClaim[i] + remainingAvailableNfts[i];
                    nftsLeft = nftsLeft - remainingAvailableNfts[i];
                    remainingAvailableNfts[i] = 0;
                }
            }
            return (nftsToClaim, nftsLeft, remainingAvailableNfts);
        } else {
            return (nftsToClaim, nftsLeft, remainingAvailableNfts);
        }
    }

    /**
     * --------------------------------------------------------------------
     * -------------------- UTILITIES TO MANAGE CLAIM EVENTS --------------
     * --------------------------------------------------------------------
     */

    function getSimpleClaimEventsActive()
        external
        view
        returns (uint256[] memory)
    {
        return _simpleClaimEventsActive;
    }

    function getRandomClaimEventsActive()
        external
        view
        returns (uint256[] memory)
    {
        return _randomClaimEventsActive;
    }

    /**
     * @dev Removes a Simple Claim event from the active list
     *
     * @param orderId ID of the event active Simple Claim event
     */
    function _removeSimpleClaimActiveEvent(uint256 orderId) private {
        // Delete the order from the active Ids list
        uint256 activeOrdersNumber = _simpleClaimEventsActive.length;
        uint256 orderIndex = 0;
        bool idFound = false;

        for (uint256 i = 0; i < activeOrdersNumber; i++) {
            if (_simpleClaimEventsActive[i] == orderId) {
                orderIndex = i;
                idFound = true;
            }
        }

        require(
            idFound,
            "The order to remove is not in the active loan orders list"
        );

        if (orderIndex != activeOrdersNumber - 1) {
            // Need to swap the order to delete with the last one and procede as above
            _simpleClaimEventsActive[orderIndex] = _simpleClaimEventsActive[
                activeOrdersNumber - 1
            ];
        }

        _simpleClaimEventsActive.pop();
    }

    /**
     * @dev Removes a Random Claim event from the active list
     *
     * @param orderId ID of the event active Random Claim event
     */
    function _removeRandomClaimActiveEvent(uint256 orderId) private {
        // Delete the order from the active Ids list
        uint256 activeOrdersNumber = _randomClaimEventsActive.length;
        uint256 orderIndex = 0;
        bool idFound = false;

        for (uint256 i = 0; i < activeOrdersNumber; i++) {
            if (_randomClaimEventsActive[i] == orderId) {
                orderIndex = i;
                idFound = true;
            }
        }

        require(
            idFound,
            "The order to remove is not in the active loan orders list"
        );

        if (orderIndex != activeOrdersNumber - 1) {
            // Need to swap the order to delete with the last one and procede as above
            _randomClaimEventsActive[orderIndex] = _randomClaimEventsActive[
                activeOrdersNumber - 1
            ];
        }

        _randomClaimEventsActive.pop();
    }

    /**
     * --------------------------------------------------------------------
     * -------------------- ERC1155 RECEVIER IMPLEMENTATION ---------------
     * --------------------------------------------------------------------
     */

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) public returns (bytes4) {
        require(
            whitelistedWallets[operator] == true,
            "The contract can't receive NFTs from this operator"
        );

        return
            bytes4(
                keccak256(
                    "onERC1155Received(address,address,uint256,uint256,bytes)"
                )
            );
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) public returns (bytes4) {
        require(
            whitelistedWallets[operator] == true,
            "The contract can't receive NFTs from this operator"
        );

        return
            bytes4(
                keccak256(
                    "onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"
                )
            );
    }
}