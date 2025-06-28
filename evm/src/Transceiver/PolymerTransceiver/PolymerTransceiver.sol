// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "wormhole-solidity-sdk/Utils.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";
import "../../libraries/TransceiverStructs.sol";
import "../../interfaces/IPolymerTransceiver.sol";
import "../../interfaces/ICrossL2ProverV2.sol";
import "./PolymerTransceiverState.sol";

/// @title PolymerTransceiver
/// @author Custom implementation for Polymer Labs integration
/// @notice Transceiver implementation for Polymer cross-chain messaging
/// @dev This contract sends and receives NTT messages authenticated through Polymer's proof system
contract PolymerTransceiver is IPolymerTransceiver, PolymerTransceiverState {
    using BytesParsing for bytes;

    string public constant POLYMER_TRANSCEIVER_VERSION = "1.0.0";

    /// @dev Event signature for NTT message emissions
    bytes32 constant NTT_MESSAGE_EVENT_SIGNATURE = keccak256("NttMessage(bytes32,bytes,uint256,bytes32)");

    constructor(
        address _nttManager,
        address _polymerProver,
        uint256 _gasLimit
    ) PolymerTransceiverState(_nttManager, _polymerProver, _gasLimit) {}

    // ==================== External Interface ===============================================

    function getTransceiverType() external pure override(ITransceiver, Transceiver) returns (string memory) {
        return "polymer";
    }

    /// @inheritdoc IPolymerTransceiver
    function receivePolymerMessage(bytes calldata proof) external whenNotPaused {
        // Validate the proof using Polymer's CrossL2ProverV2
        (
            uint256 sourceChainId,
            address sourceContract,
            bytes memory topics,
            bytes memory unindexedData
        ) = ICrossL2ProverV2(polymerProver).validateEvent(proof);

        // Convert chain ID to uint16 (Wormhole format)
        uint16 sourceChain = _polymerToWormholeChainId(sourceChainId);
        
        // Verify the source contract is a registered peer
        bytes32 sourcePeer = toWormholeFormat(sourceContract);
        if (getPolymerPeer(sourceChain) != sourcePeer) {
            revert InvalidPolymerPeer(sourceChain, sourcePeer);
        }

        // Extract proof identifier for replay protection
        (
            uint32 srcChain,
            uint64 blockNumber,
            uint16 receiptIndex,
            uint8 logIndex
        ) = ICrossL2ProverV2(polymerProver).inspectLogIdentifier(proof);
        
        // Create unique proof ID using all four fields from Polymer proof
        bytes32 proofId = keccak256(abi.encode(
            srcChain,
            blockNumber,
            receiptIndex,
            logIndex
        ));
        
        // Check for replay attack
        if (isProofConsumed(proofId)) {
            revert ProofAlreadyConsumed(proofId);
        }
        _setProofConsumed(proofId);

        // Parse topics to verify event signature
        bytes32[] memory topicsArray = _parseTopics(topics);
        if (topicsArray.length == 0 || topicsArray[0] != NTT_MESSAGE_EVENT_SIGNATURE) {
            revert InvalidEventSignature(topicsArray.length > 0 ? topicsArray[0] : bytes32(0));
        }

        // Decode the message data from unindexed data
        (
            bytes32 recipientNttManagerAddress,
            bytes memory encodedTransceiverPayload,
            uint256 deliveryPayment,
            bytes32 refundAddress
        ) = abi.decode(unindexedData, (bytes32, bytes, uint256, bytes32));

        // Parse the transceiver message
        TransceiverStructs.TransceiverMessage memory parsedTransceiverMessage;
        TransceiverStructs.NttManagerMessage memory parsedNttManagerMessage;
        (parsedTransceiverMessage, parsedNttManagerMessage) = TransceiverStructs
            .parseTransceiverAndNttManagerMessage(POLYMER_TRANSCEIVER_PAYLOAD_PREFIX, encodedTransceiverPayload);

        emit ReceivedPolymerMessage(proofId, sourceChain, sourcePeer);

        // Deliver to NTT Manager
        _deliverToNttManager(
            sourceChain,
            parsedTransceiverMessage.sourceNttManagerAddress,
            parsedTransceiverMessage.recipientNttManagerAddress,
            parsedNttManagerMessage
        );
    }

    /// @inheritdoc IPolymerTransceiver
    function parsePolymerTransceiverInstruction(
        bytes memory encoded
    ) public pure returns (PolymerTransceiverInstruction memory instruction) {
        if (encoded.length == 0) {
            instruction.gasLimit = 0; // Use default
            return instruction;
        }

        uint256 offset = 0;
        (instruction.gasLimit, offset) = encoded.asUint256Unchecked(offset);
        encoded.checkLength(offset);
    }

    /// @inheritdoc IPolymerTransceiver
    function encodePolymerTransceiverInstruction(
        PolymerTransceiverInstruction memory instruction
    ) public pure returns (bytes memory) {
        return abi.encodePacked(instruction.gasLimit);
    }

    // ==================== Internal ========================================================

    function _quoteDeliveryPrice(
        uint16 targetChain,
        TransceiverStructs.TransceiverInstruction memory instruction
    ) internal view override returns (uint256 nativePriceQuote) {
        if (!isPolymerChainEnabled(targetChain)) {
            revert ChainNotEnabled(targetChain);
        }

        // Polymer pricing could be based on gas limit
        PolymerTransceiverInstruction memory polyIns = 
            parsePolymerTransceiverInstruction(instruction.payload);
        
        uint256 gasToUse = polyIns.gasLimit > 0 ? polyIns.gasLimit : gasLimit;
        
        // For now, return a base fee + gas-based calculation
        // This should be adjusted based on Polymer's actual pricing model
        uint256 baseFee = 0.001 ether;
        uint256 gasFee = gasToUse * tx.gasprice;
        
        return baseFee + gasFee;
    }

    function _sendMessage(
        uint16 recipientChain,
        uint256 deliveryPayment,
        address caller,
        bytes32 recipientNttManagerAddress,
        bytes32 refundAddress,
        TransceiverStructs.TransceiverInstruction memory instruction,
        bytes memory nttManagerMessage
    ) internal override {
        if (!isPolymerChainEnabled(recipientChain)) {
            revert ChainNotEnabled(recipientChain);
        }

        // Build the transceiver message
        (
            TransceiverStructs.TransceiverMessage memory transceiverMessage,
            bytes memory encodedTransceiverPayload
        ) = TransceiverStructs.buildAndEncodeTransceiverMessage(
            POLYMER_TRANSCEIVER_PAYLOAD_PREFIX,
            toWormholeFormat(caller),
            recipientNttManagerAddress,
            nttManagerMessage,
            new bytes(0)
        );

        // Emit event that Polymer will capture and relay.
        emit NttMessage(recipientNttManagerAddress, encodedTransceiverPayload, deliveryPayment, refundAddress);
        
        // Emit event for consistent accounting. 
        emit SendTransceiverMessage(recipientChain, transceiverMessage);
    }

    // ==================== Internal Helpers ================================================

    /// @dev Parse topics from bytes to bytes32 array
    function _parseTopics(bytes memory topics) internal pure returns (bytes32[] memory) {
        if (topics.length % 32 != 0) {
            revert InvalidTopicsLength(topics.length);
        }
        
        uint256 numTopics = topics.length / 32;
        bytes32[] memory topicsArray = new bytes32[](numTopics);
        
        for (uint256 i = 0; i < numTopics; i++) {
            uint256 offset = i * 32;
            bytes32 topic;
            assembly {
                topic := mload(add(add(topics, 0x20), offset))
            }
            topicsArray[i] = topic;
        }
        
        return topicsArray;
    }

    /// @dev Convert Polymer chain ID to Wormhole chain ID format
    /// @notice This mapping should be configured based on actual chain IDs
    function _polymerToWormholeChainId(uint256 polymerChainId) internal pure returns (uint16) {
        // TODO: Make these chain mappings configurable or handle the transformation upstream. 
        if (polymerChainId == 1) return 2; // Ethereum
        if (polymerChainId == 137) return 5; // Polygon
        if (polymerChainId == 10) return 24; // Optimism
        if (polymerChainId == 42161) return 23; // Arbitrum
        
        revert UnsupportedChainId(polymerChainId);
    }

    /// @dev Fallback to receive ETH for refunds
    receive() external payable {}
}
