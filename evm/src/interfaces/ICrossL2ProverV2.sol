// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

/// @title ICrossL2ProverV2
/// @notice Interface for Polymer's CrossL2ProverV2 contract
interface ICrossL2ProverV2 {
    /// @notice Validates a cross-chain event and returns its details
    /// @param proof The encoded proof payload
    /// @return sourceChainId The chain ID where the event originated
    /// @return sourceContract The contract address that emitted the event
    /// @return topics The concatenated event topics
    /// @return unindexedData The ABI-encoded non-indexed event parameters
    function validateEvent(
        bytes calldata proof
    ) external view returns (
        uint256 sourceChainId,
        address sourceContract,
        bytes memory topics,
        bytes memory unindexedData
    );

    /// @notice Inspects the log identifier from a proof
    /// @param proof The encoded proof payload
    /// @return srcChain The source chain ID (uint32)
    /// @return blockNumber The block number (uint64)
    /// @return receiptIndex The receipt index (uint16)
    /// @return logIndex The log index within the block (uint8)
    function inspectLogIdentifier(
        bytes calldata proof
    ) external pure returns (
        uint32 srcChain,
        uint64 blockNumber,
        uint16 receiptIndex,
        uint8 logIndex
    );

    /// @notice Inspects the Polymer state from a proof
    /// @param proof The encoded proof payload
    /// @return stateRoot The Polymer state root
    /// @return height The block height (uint64)
    /// @return signature The sequencer's signature
    function inspectPolymerState(
        bytes calldata proof
    ) external pure returns (
        bytes32 stateRoot,
        uint64 height,
        bytes calldata signature
    );
}