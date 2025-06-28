// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";
import "../src/Transceiver/PolymerTransceiver/PolymerTransceiver.sol";
import "../src/interfaces/ICrossL2ProverV2.sol";
import "../src/mocks/DummyToken.sol";
import "../src/NttManager/NttManager.sol";
import "../src/interfaces/IManagerBase.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "wormhole-solidity-sdk/Utils.sol";
import "./libraries/NttManagerHelpers.sol";

contract MockCrossL2ProverV2 is ICrossL2ProverV2 {
    mapping(bytes32 => bool) public validProofs;
    
    struct MockProof {
        uint256 sourceChainId;
        address sourceContract;
        bytes topics;
        bytes unindexedData;
        uint256 logIndex;
    }
    
    mapping(bytes32 => MockProof) public proofs;
    
    function setValidProof(
        bytes32 proofId,
        uint256 _sourceChainId,
        address _sourceContract,
        bytes memory _topics,
        bytes memory _unindexedData,
        uint256 _logIndex
    ) external {
        validProofs[proofId] = true;
        proofs[proofId] = MockProof({
            sourceChainId: _sourceChainId,
            sourceContract: _sourceContract,
            topics: _topics,
            unindexedData: _unindexedData,
            logIndex: _logIndex
        });
    }
    
    function validateEvent(
        bytes calldata proof
    ) external view returns (
        uint256 sourceChainId,
        address sourceContract,
        bytes memory topics,
        bytes memory unindexedData
    ) {
        bytes32 proofId = keccak256(proof);
        require(validProofs[proofId], "Invalid proof");
        
        MockProof memory p = proofs[proofId];
        return (p.sourceChainId, p.sourceContract, p.topics, p.unindexedData);
    }
    
    function inspectLogIdentifier(
        bytes calldata proof
    ) external view returns (
        uint256 sourceChain,
        uint256 blockNumber,
        uint256 receiptIndex,
        uint256 logIndex,
        uint256 logIndexWithinTransaction
    ) {
        bytes32 proofId = keccak256(proof);
        require(validProofs[proofId], "Invalid proof");
        
        MockProof memory p = proofs[proofId];
        return (p.sourceChainId, 1000, 0, p.logIndex, p.logIndex);
    }
    
    function inspectPolymerState(
        bytes calldata
    ) external pure returns (
        bytes32 stateRoot,
        uint256 blockHeight,
        bytes memory sequencerSignature
    ) {
        return (bytes32(0), 1000, new bytes(0));
    }
}

contract PolymerTransceiverTest is Test {
    PolymerTransceiver transceiver;
    MockCrossL2ProverV2 mockProver;
    NttManager nttManager;
    DummyToken token;
    
    uint16 constant SOURCE_CHAIN = 2; // Ethereum
    uint16 constant TARGET_CHAIN = 5; // Polygon
    uint16 constant CHAIN_ID = 7;
    address constant USER = address(0x123);
    
    function setUp() public {
        // Deploy mock token
        token = new DummyToken();
        
        // Deploy NTT Manager implementation
        NttManager implementation = new NttManager(
            address(token), 
            IManagerBase.Mode.LOCKING, 
            CHAIN_ID, 
            1 days, 
            false
        );
        
        // Deploy proxy and initialize
        nttManager = NttManager(address(new ERC1967Proxy(address(implementation), "")));
        nttManager.initialize();
        
        // Deploy mock prover
        mockProver = new MockCrossL2ProverV2();
        
        // Deploy Polymer transceiver
        transceiver = new PolymerTransceiver(
            address(nttManager),
            address(mockProver),
            500000 // gasLimit
        );
        
        // Initialize transceiver
        transceiver.initialize();
        
        // Set up NTT Manager
        nttManager.setTransceiver(address(transceiver));
        nttManager.setThreshold(1);
        
        // Set up peers
        vm.prank(nttManager.owner());
        transceiver.setPolymerPeer(TARGET_CHAIN, toWormholeFormat(address(0x456)));
        
        vm.prank(nttManager.owner());
        transceiver.setIsPolymerChainEnabled(TARGET_CHAIN, true);
    }
    
    function test_getTransceiverType() public {
        assertEq(transceiver.getTransceiverType(), "polymer");
    }
    
    function test_setPolymerPeer() public {
        uint16 newChain = 10;
        bytes32 peerAddress = toWormholeFormat(address(0x789));
        
        vm.prank(nttManager.owner());
        transceiver.setPolymerPeer(newChain, peerAddress);
        
        assertEq(transceiver.getPolymerPeer(newChain), peerAddress);
    }
    
    function test_enableChain() public {
        uint16 newChain = 10;
        
        vm.prank(nttManager.owner());
        transceiver.setIsPolymerChainEnabled(newChain, true);
        
        assertTrue(transceiver.isPolymerChainEnabled(newChain));
    }
    
    function test_quoteDeliveryPrice() public {
        TransceiverStructs.TransceiverInstruction memory instruction;
        instruction.index = 0;
        instruction.payload = new bytes(0);
        
        uint256 price = transceiver.quoteDeliveryPrice(TARGET_CHAIN, instruction);
        assertGt(price, 0);
    }
    
    function test_sendMessage() public {
        // Mint tokens to user
        token.mintDummy(USER, 1000);
        
        // Approve and transfer
        vm.startPrank(USER);
        token.approve(address(nttManager), 1000);
        
        // Note: We expect an NttMessage event to be emitted
        
        nttManager.transfer{value: 0.01 ether}(
            1000,
            TARGET_CHAIN,
            toWormholeFormat(USER),
            toWormholeFormat(USER),
            false,
            new bytes(0)
        );
        vm.stopPrank();
    }
    
    function test_receivePolymerMessage() public {
        // Set up a mock proof
        bytes32 proofId = keccak256("test_proof");
        uint256 sourceChainId = 1; // Ethereum
        address sourceContract = address(0x456);
        
        // Create topics (event signature)
        bytes memory topics = abi.encodePacked(
            keccak256("NttMessage(bytes32,bytes)")
        );
        
        // Create sample NTT message
        TransceiverStructs.NttManagerMessage memory nttMsg = TransceiverStructs.NttManagerMessage({
            id: bytes32(uint256(1)),
            sender: toWormholeFormat(USER),
            payload: abi.encode("test payload")
        });
        
        TransceiverStructs.TransceiverMessage memory transceiverMsg = TransceiverStructs.TransceiverMessage({
            sourceNttManagerAddress: toWormholeFormat(address(0x456)),
            recipientNttManagerAddress: toWormholeFormat(address(nttManager)),
            nttManagerPayload: TransceiverStructs.encodeNttManagerMessage(nttMsg),
            transceiverPayload: new bytes(0)
        });
        
        bytes memory encodedPayload = TransceiverStructs.encodeTransceiverMessage(
            bytes4(0x504F4C59), // POLYMER_TRANSCEIVER_PAYLOAD_PREFIX
            transceiverMsg
        );
        
        bytes memory unindexedData = abi.encode(
            toWormholeFormat(address(nttManager)),
            encodedPayload
        );
        
        // Set up the mock proof
        mockProver.setValidProof(
            proofId,
            sourceChainId,
            sourceContract,
            topics,
            unindexedData,
            1
        );
        
        // Set up peer mapping for source chain
        vm.prank(nttManager.owner());
        transceiver.setPolymerPeer(SOURCE_CHAIN, toWormholeFormat(sourceContract));
        
        // Call receivePolymerMessage
        bytes memory proof = abi.encode(proofId);
        
        // Note: We expect a ReceivedPolymerMessage event to be emitted
        
        transceiver.receivePolymerMessage(proof);
        
        // Verify proof is consumed
        assertTrue(transceiver.isProofConsumed(
            keccak256(abi.encodePacked(sourceChainId, sourceContract, uint256(1)))
        ));
    }
    
    function test_revertOnReplayAttack() public {
        // Set up and execute a valid message first
        test_receivePolymerMessage();
        
        // Try to replay the same proof
        bytes32 proofId = keccak256("test_proof");
        bytes memory proof = abi.encode(proofId);
        
        vm.expectRevert();
        transceiver.receivePolymerMessage(proof);
    }
    
    function test_revertOnInvalidPeer() public {
        bytes32 proofId = keccak256("invalid_peer_proof");
        uint256 sourceChainId = 1;
        address invalidSourceContract = address(0x999); // Not registered as peer
        
        bytes memory topics = abi.encodePacked(
            keccak256("NttMessage(bytes32,bytes)")
        );
        
        bytes memory unindexedData = abi.encode(
            toWormholeFormat(address(nttManager)),
            new bytes(0)
        );
        
        mockProver.setValidProof(
            proofId,
            sourceChainId,
            invalidSourceContract,
            topics,
            unindexedData,
            1
        );
        
        bytes memory proof = abi.encode(proofId);
        
        vm.expectRevert();
        transceiver.receivePolymerMessage(proof);
    }
}