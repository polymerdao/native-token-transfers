# Polymer Transceiver for Wormhole Native Token Transfer

## Overview

The Polymer Transceiver integrates Polymer Labs' cross-chain proof system with Wormhole's Native Token Transfer (NTT) protocol. This implementation allows tokens to be transferred across chains using Polymer's cryptographic proof verification system.

## Architecture

### Core Components

1. **PolymerTransceiver.sol** - Main transceiver contract implementing cross-chain messaging
2. **PolymerTransceiverState.sol** - Storage management and configuration
3. **IPolymerTransceiver.sol** - Interface definitions
4. **ICrossL2ProverV2.sol** - Interface for Polymer's prover contract

### Key Features

- **Proof-based Verification**: Uses Polymer's CrossL2ProverV2 for cryptographic proof validation
- **Replay Protection**: Prevents replay attacks using proof identifiers
- **Peer Management**: Maintains whitelist of authorized cross-chain contracts
- **Event-based Messaging**: Emits events that Polymer captures and relays across chains

## Deployment

### Prerequisites

1. Deployed NTT Manager contract
2. Deployed Polymer CrossL2ProverV2 contract
3. Network connectivity between source and destination chains

### Deployment Steps

```solidity
// 1. Deploy the Polymer Transceiver
PolymerTransceiver transceiver = new PolymerTransceiver(
    address(nttManager),      // NTT Manager contract address
    address(polymerProver),   // Polymer CrossL2ProverV2 address
    500000                    // Gas limit for cross-chain calls
);

// 2. Initialize the transceiver
transceiver.initialize();

// 3. Register with NTT Manager
nttManager.setTransceiver(address(transceiver));
```

## Configuration

### Setting up Cross-Chain Peers

```solidity
// Enable a target chain for Polymer messaging
transceiver.setIsPolymerChainEnabled(targetChainId, true);

// Register peer contract on target chain
transceiver.setPolymerPeer(
    targetChainId, 
    toWormholeFormat(peerContractAddress)
);
```

### Chain ID Mapping

The transceiver includes a mapping function `_polymerToWormholeChainId()` that converts Polymer chain IDs to Wormhole format:

- Ethereum (1) → Wormhole chain 2
- Polygon (137) → Wormhole chain 5  
- Optimism (10) → Wormhole chain 24
- Arbitrum (42161) → Wormhole chain 23

Update this mapping based on your specific chain requirements.

## Message Flow

### Sending Messages

1. User initiates transfer via NTT Manager
2. NTT Manager calls `transceiver.sendMessage()`
3. Transceiver emits `NttMessage` event
4. Polymer captures event and creates proof
5. Proof is relayed to destination chain

### Receiving Messages

1. Relayer calls `transceiver.receivePolymerMessage(proof)`
2. Transceiver validates proof using CrossL2ProverV2
3. Verifies source peer is authorized
4. Checks for replay attacks
5. Delivers message to NTT Manager

## Security Considerations

### Proof Validation

- All incoming proofs are validated using Polymer's CrossL2ProverV2
- Event signatures must match expected NTT message format
- Source contracts must be registered peers

### Replay Protection

- Each proof is assigned a unique identifier based on chain ID, contract, and log index
- Consumed proofs are tracked in storage to prevent reuse

### Access Control

- Only NTT Manager can send messages
- Only contract owner can configure peers and chains
- Pausable functionality for emergency stops

## Events

```solidity
// Emitted when sending a message
event NttMessage(bytes32 indexed recipientNttManagerAddress, bytes encodedPayload);

// Emitted when receiving a verified message  
event ReceivedPolymerMessage(bytes32 proofId, uint16 sourceChain, bytes32 sourcePeer);

// Configuration events
event SetPolymerPeer(uint16 chainId, bytes32 peerContract);
event SetIsPolymerChainEnabled(uint16 chainId, bool isEnabled);
```

## Error Handling

Common errors and their meanings:

- `InvalidPolymerPeer`: Source contract not registered as authorized peer
- `ProofAlreadyConsumed`: Attempt to replay a used proof
- `InvalidEventSignature`: Event doesn't match expected NTT message format
- `ChainNotEnabled`: Target chain not configured for Polymer messaging
- `UnsupportedChainId`: Chain ID not in mapping table

## Testing

Run the test suite:

```bash
forge test --match-contract PolymerTransceiverTest
```

Key test scenarios:
- Message sending and receiving
- Proof validation and replay protection
- Peer management and access control
- Error conditions and edge cases

## Integration Notes

### Gas Optimization

- Proof validation can be gas-intensive
- Consider batch processing for multiple messages
- Monitor gas costs on different networks

### Monitoring

- Track proof consumption for replay detection
- Monitor event emissions for message flow
- Set up alerts for configuration changes

### Upgrades

- Contract follows proxy upgrade pattern
- State variables use storage slots to avoid conflicts
- Test upgrade paths thoroughly before deployment

## Support

For technical support or questions:
- Review Polymer Labs documentation: https://docs.polymerlabs.org
- Check Wormhole NTT documentation  
- File issues in the respective GitHub repositories