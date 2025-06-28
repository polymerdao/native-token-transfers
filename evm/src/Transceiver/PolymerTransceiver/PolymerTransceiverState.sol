// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "wormhole-solidity-sdk/Utils.sol";
import "../../libraries/BooleanFlag.sol";
import "../../libraries/TransceiverStructs.sol";
import "../../interfaces/IPolymerTransceiverState.sol";
import "../../interfaces/INttManager.sol";
import "../Transceiver.sol";

abstract contract PolymerTransceiverState is IPolymerTransceiverState, Transceiver {
    using BooleanFlagLib for bool;
    using BooleanFlagLib for BooleanFlag;

    // ==================== Immutables ===============================================
    
    /// @dev Address of the Polymer CrossL2ProverV2 contract
    address public immutable polymerProver;
    
    /// @dev Gas limit for cross-chain calls
    uint256 public immutable gasLimit;
    
    // ==================== Constants ================================================
    
    /// @dev Prefix for all Polymer TransceiverMessage payloads
    bytes4 constant POLYMER_TRANSCEIVER_PAYLOAD_PREFIX = 0x504F4C59; // 'POLY'
    
    /// @dev Prefix for Polymer transceiver initialization payloads
    bytes4 constant POLYMER_TRANSCEIVER_INIT_PREFIX = 0x504F4C49; // 'POLI'
    
    /// @dev Prefix for Polymer peer registration payloads
    bytes4 constant POLYMER_PEER_REGISTRATION_PREFIX = 0x504F4C52; // 'POLR'

    constructor(
        address _nttManager,
        address _polymerProver,
        uint256 _gasLimit
    ) Transceiver(_nttManager) {
        polymerProver = _polymerProver;
        gasLimit = _gasLimit;
    }

    function _initialize() internal override {
        super._initialize();
        _initializeTransceiver();
    }

    function _initializeTransceiver() internal {
        TransceiverStructs.TransceiverInit memory init = TransceiverStructs.TransceiverInit({
            transceiverIdentifier: POLYMER_TRANSCEIVER_INIT_PREFIX,
            nttManagerAddress: toWormholeFormat(nttManager),
            nttManagerMode: INttManager(nttManager).getMode(),
            tokenAddress: toWormholeFormat(nttManagerToken),
            tokenDecimals: INttManager(nttManager).tokenDecimals()
        });
        
        // Emit initialization event for Polymer to capture
        emit PolymerTransceiverInitialized(
            toWormholeFormat(nttManager),
            toWormholeFormat(nttManagerToken),
            INttManager(nttManager).tokenDecimals()
        );
    }

    function _checkImmutables() internal view override {
        super._checkImmutables();
        assert(this.polymerProver() == polymerProver);
        assert(this.gasLimit() == gasLimit);
    }

    // =============== Storage ===============================================
    
    bytes32 private constant POLYMER_CONSUMED_PROOFS_SLOT =
        bytes32(uint256(keccak256("polymerTransceiver.consumedProofs")) - 1);
    
    bytes32 private constant POLYMER_PEERS_SLOT =
        bytes32(uint256(keccak256("polymerTransceiver.peers")) - 1);
    
    bytes32 private constant POLYMER_ENABLED_CHAINS_SLOT =
        bytes32(uint256(keccak256("polymerTransceiver.enabledChains")) - 1);

    // =============== Storage Setters/Getters ========================================
    
    function _getPolymerConsumedProofsStorage()
        internal
        pure
        returns (mapping(bytes32 => bool) storage $)
    {
        uint256 slot = uint256(POLYMER_CONSUMED_PROOFS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }
    
    function _getPolymerPeersStorage()
        internal
        pure
        returns (mapping(uint16 => bytes32) storage $)
    {
        uint256 slot = uint256(POLYMER_PEERS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }
    
    function _getPolymerEnabledChainsStorage()
        internal
        pure
        returns (mapping(uint16 => BooleanFlag) storage $)
    {
        uint256 slot = uint256(POLYMER_ENABLED_CHAINS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    // =============== Public Getters ======================================================
    
    /// @inheritdoc IPolymerTransceiverState
    function isProofConsumed(bytes32 proofId) public view returns (bool) {
        return _getPolymerConsumedProofsStorage()[proofId];
    }
    
    /// @inheritdoc IPolymerTransceiverState
    function getPolymerPeer(uint16 chainId) public view returns (bytes32) {
        return _getPolymerPeersStorage()[chainId];
    }
    
    /// @inheritdoc IPolymerTransceiverState
    function isPolymerChainEnabled(uint16 chainId) public view returns (bool) {
        return _getPolymerEnabledChainsStorage()[chainId].toBool();
    }

    // =============== Admin ===============================================================
    
    /// @inheritdoc IPolymerTransceiverState
    function setPolymerPeer(uint16 peerChainId, bytes32 peerContract) external payable onlyOwner {
        if (peerChainId == 0) {
            revert InvalidPolymerChainIdZero();
        }
        if (peerContract == bytes32(0)) {
            revert InvalidPolymerPeerZeroAddress();
        }
        
        bytes32 oldPeerContract = _getPolymerPeersStorage()[peerChainId];
        
        // Prevent updating existing peers for security
        if (oldPeerContract != bytes32(0)) {
            revert PeerAlreadySet(peerChainId, oldPeerContract);
        }
        
        _getPolymerPeersStorage()[peerChainId] = peerContract;
        
        // Emit peer registration event for Polymer
        emit SetPolymerPeer(peerChainId, peerContract);
    }
    
    /// @inheritdoc IPolymerTransceiverState
    function setIsPolymerChainEnabled(uint16 chainId, bool isEnabled) external onlyOwner {
        if (chainId == 0) {
            revert InvalidPolymerChainIdZero();
        }
        _getPolymerEnabledChainsStorage()[chainId] = isEnabled.toWord();
        
        emit SetIsPolymerChainEnabled(chainId, isEnabled);
    }

    // ============= Internal ===============================================================
    
    function _setProofConsumed(bytes32 proofId) internal {
        _getPolymerConsumedProofsStorage()[proofId] = true;
    }
}