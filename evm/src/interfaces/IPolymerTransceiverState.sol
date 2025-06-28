// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

interface IPolymerTransceiverState {
    /// @notice Emitted when a Polymer peer contract is set
    /// @param chainId The Polymer chain ID of the peer
    /// @param peerContract The address of the peer contract in bytes32 format
    event SetPolymerPeer(uint16 chainId, bytes32 peerContract);
    
    /// @notice Emitted when a chain is enabled or disabled for Polymer
    /// @param chainId The chain ID being configured
    /// @param isEnabled Whether the chain is enabled for Polymer messaging
    event SetIsPolymerChainEnabled(uint16 chainId, bool isEnabled);
    
    /// @notice Emitted when the Polymer transceiver is initialized
    /// @param nttManagerAddress The address of the NTT Manager
    /// @param tokenAddress The address of the token being transferred
    /// @param tokenDecimals The number of decimals for the token
    event PolymerTransceiverInitialized(
        bytes32 nttManagerAddress,
        bytes32 tokenAddress,
        uint8 tokenDecimals
    );

    /// @notice Error when the chain ID is zero
    /// @dev Selector 0x09e7c4e5
    error InvalidPolymerChainIdZero();
    
    /// @notice Error when the peer address is zero
    /// @dev Selector 0xc4e3b4d5
    error InvalidPolymerPeerZeroAddress();
    
    /// @notice Error when trying to update an already set peer
    /// @dev Selector 0x9a14b0d1
    /// @param chainId The chain ID of the peer
    /// @param existingPeer The existing peer address
    error PeerAlreadySet(uint16 chainId, bytes32 existingPeer);

    /// @notice Check if a proof has been consumed
    /// @param proofId The identifier of the proof
    /// @return consumed Whether the proof has been consumed
    function isProofConsumed(bytes32 proofId) external view returns (bool consumed);
    
    /// @notice Get the peer contract address for a given chain
    /// @param chainId The chain ID to query
    /// @return peerContract The peer contract address in bytes32 format
    function getPolymerPeer(uint16 chainId) external view returns (bytes32 peerContract);
    
    /// @notice Check if a chain is enabled for Polymer messaging
    /// @param chainId The chain ID to query
    /// @return enabled Whether the chain is enabled
    function isPolymerChainEnabled(uint16 chainId) external view returns (bool enabled);
    
    /// @notice Set the peer contract address for a given chain
    /// @param peerChainId The chain ID of the peer
    /// @param peerContract The address of the peer contract in bytes32 format
    function setPolymerPeer(uint16 peerChainId, bytes32 peerContract) external payable;
    
    /// @notice Enable or disable a chain for Polymer messaging
    /// @param chainId The chain ID to configure
    /// @param isEnabled Whether to enable or disable the chain
    function setIsPolymerChainEnabled(uint16 chainId, bool isEnabled) external;
}