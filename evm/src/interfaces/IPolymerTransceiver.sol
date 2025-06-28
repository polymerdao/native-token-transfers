// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "./ITransceiver.sol";
import "../libraries/TransceiverStructs.sol";

interface IPolymerTransceiver is ITransceiver {
    /// @notice Polymer-specific transceiver instruction
    struct PolymerTransceiverInstruction {
        uint256 gasLimit; // Optional gas limit override
    }

    /// @notice Emitted when sending an NTT message via Polymer
    /// @param recipientNttManagerAddress The recipient NTT manager address
    /// @param encodedPayload The encoded transceiver payload
    /// @param deliveryPayment The payment amount for delivery
    /// @param refundAddress The address to refund excess payment to
    event NttMessage(
        bytes32 indexed recipientNttManagerAddress, 
        bytes encodedPayload,
        uint256 deliveryPayment,
        bytes32 refundAddress
    );

    /// @notice Emitted when a message is sent via the transceiver
    /// @param recipientChain The chain ID of the recipient
    /// @param message The transceiver message being sent
    event SendTransceiverMessage(
        uint16 recipientChain,
        TransceiverStructs.TransceiverMessage message
    );

    /// @notice Emitted when a Polymer message is received and validated
    /// @param proofId The unique identifier of the proof
    /// @param sourceChain The source chain ID
    /// @param sourcePeer The source peer address
    event ReceivedPolymerMessage(bytes32 proofId, uint16 sourceChain, bytes32 sourcePeer);

    /// @notice Error when peer validation fails
    /// @param chainId The chain ID
    /// @param peerAddress The peer address that failed validation
    error InvalidPolymerPeer(uint16 chainId, bytes32 peerAddress);

    /// @notice Error when a proof has already been consumed
    /// @param proofId The proof identifier
    error ProofAlreadyConsumed(bytes32 proofId);

    /// @notice Error when event signature doesn't match expected
    /// @param signature The invalid signature
    error InvalidEventSignature(bytes32 signature);

    /// @notice Error when chain is not enabled
    /// @param chainId The chain ID that is not enabled
    error ChainNotEnabled(uint16 chainId);

    /// @notice Error when refund fails
    /// @param recipient The refund recipient
    /// @param amount The refund amount
    error RefundFailed(address recipient, uint256 amount);

    /// @notice Error when topics length is invalid
    /// @param length The invalid length
    error InvalidTopicsLength(uint256 length);

    /// @notice Error when chain ID is not supported
    /// @param chainId The unsupported chain ID
    error UnsupportedChainId(uint256 chainId);

    /// @notice Receive a message from Polymer with proof validation
    /// @param proof The Polymer proof to validate
    function receivePolymerMessage(bytes calldata proof) external;

    /// @notice Parse Polymer transceiver instruction
    /// @param encoded The encoded instruction
    /// @return instruction The parsed instruction
    function parsePolymerTransceiverInstruction(
        bytes memory encoded
    ) external pure returns (PolymerTransceiverInstruction memory instruction);

    /// @notice Encode Polymer transceiver instruction
    /// @param instruction The instruction to encode
    /// @return encoded The encoded instruction
    function encodePolymerTransceiverInstruction(
        PolymerTransceiverInstruction memory instruction
    ) external pure returns (bytes memory encoded);
}