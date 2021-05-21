// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/drafts/EIP712.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IDai.sol";
import "./interfaces/IProofOfHumanity.sol";
import "./interfaces/IRNG.sol";
import "./Gazzeth.sol";

contract Protocol is EIP712 {

    using SafeMath for uint256;

    modifier onlyExistentPublications(uint256 _publicationId) {
        require(_publicationId < publicationId, "Publication does not exist");
        _;
    }

    modifier onlyPublicationJurors(uint256 _publicationId) {
        require(publications[_publicationId].votation.jurors[msg.sender], "You are not a juror for this publication");
        _;
    }

    enum VoteValue {
        None,
        True,
        False,
        Unqualified
    }
    
    struct Vote {
        uint256 nonce;
        VoteValue value;
        bytes32 commitment;
        string justification;
    }

    struct Votation {
        mapping (address => bool) jurors;
        mapping (address => Vote) votes;
    }

    struct Publication {
        string hash;
        address author;
        uint256 topicId;
        uint256 publishDate;
        Votation votation;
    }

    struct Topic {
        string name;
        string description;
        bool active;
        uint256 publishPrice;
        uint256 jurorPrice;
        uint256 commitPhaseDuration;
        uint256 revealPhaseDuration;
        mapping (address => bool) jurors;
        uint256 jurorQuantity;
    }

    bytes32 immutable REVEAL_VOTE_TYPEHASH;

    Gazzeth gazzeth;
    IDai dai;
    IProofOfHumanity proofOfHumanity;
    IRNG rng;
    uint256 minTopicJurorsQuantity;
    uint256 votingJurorsQuantity;
    uint256 publicationId;
    mapping (uint256 => Publication) publications;
    mapping (uint256 => Topic) topics;

    constructor(
        Gazzeth _gazzeth,
        IDai _dai,
        IProofOfHumanity _proofOfHumanity,
        IRNG _rng,
        uint256 _minTopicJurorsQuantity,
        uint256 _votingJurorsQuantity
    ) EIP712("Protocol", "1") {
        gazzeth = _gazzeth;
        dai = _dai;
        proofOfHumanity = _proofOfHumanity;
        rng = _rng;
        minTopicJurorsQuantity = _minTopicJurorsQuantity;
        votingJurorsQuantity = _votingJurorsQuantity;
        REVEAL_VOTE_TYPEHASH = keccak256("RevealVote(uint256 publicationId,VoteValue vote)");
    }

    function getCommitmentNonce(address _juror, uint256 _publicationId) external view returns (uint256) {
        return publications[_publicationId].votation.votes[_juror].nonce;
    }

    function publish(
        string calldata _publicationHash,
        uint256 _topicId,
        uint256 _nonce,
        uint256 _expiry,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (uint256) {
        require(topics[_topicId].active, "Inactive topic");
        require(topics[_topicId].jurorQuantity >= minTopicJurorsQuantity, "Insuficient jurors subscribed to the topic");
        require(dai.balanceOf(msg.sender) >= topics[_topicId].publishPrice, "Insuficient DAI to publish");
        Publication storage publication = publications[publicationId];
        publication.hash = _publicationHash;
        publication.author = msg.sender;
        publication.publishDate = block.timestamp;
        publication.topicId = _topicId;
        setJurors(publicationId);
        dai.permit(msg.sender, address(this), _nonce, _expiry, true, _v, _r, _s);
        dai.transferFrom(msg.sender, address(this), topics[_topicId].publishPrice);
        return publicationId++;
    }

    /**
     ** commitment = keccak256(v,r,s), With v, r & s parts of ECDSA signature of _hashTypedDataV4(hashStruct)
     ** Where hashStruct = keccak256(
     **                       keccak256("RevealVote(uint256 publicationId,VoteValue vote,uint256 nonce)"),
     **                       publicationId,
     **                       vote,
     **                       nonce
     **                    )
     */
    function commitVote(
        uint256 _publicationId, bytes32 _commitment, uint256 _nonce
    ) external onlyExistentPublications(_publicationId) onlyPublicationJurors(_publicationId) {
        require(timeToFinishCommitPhase(_publicationId) > 0, "Vote commit phase has already finished");
        require(_nonce >= publications[_publicationId].votation.votes[msg.sender].nonce, "Nonce must be greater than the last one");
        publications[_publicationId].votation.votes[msg.sender].commitment = _commitment;
        publications[_publicationId].votation.votes[msg.sender].nonce = _nonce + 1;
    }

    function revealVote(
        uint256 _publicationId, VoteValue _vote, string calldata _justification, uint8 _v, bytes32 _r, bytes32 _s
    ) external onlyExistentPublications(_publicationId) onlyPublicationJurors(_publicationId) {
        /**
         ** TODO: Even reverting, I think vote value is now public on etherscan. Penalize DAI deposit instead of reverting?
         ** Maybe setting a penalization flag and return a bool indicating it, then penalize DAI even if vote was wright
         */
        require(timeToFinishCommitPhase(_publicationId) == 0, "Vote commit phase has not finished yet");
        require(publications[_publicationId].votation.votes[msg.sender].nonce > 0, "Missing vote commitment");
        require(timeToFinishRevealPhase(_publicationId) > 0, "Vote reveal phase has already finished");
        require(
            publications[_publicationId].votation.votes[msg.sender].commitment == keccak256(abi.encode(_v, _r, _s)),
            "Invalid vote reveal: revealed values do not match commitment"
        );
        require(
            ECDSA.recover(_hashTypedDataV4(hashStruct(_publicationId, _vote)), _v, _r, _s) == msg.sender,
            "Invalid vote reveal: invalid signature"
        );
        publications[_publicationId].votation.votes[msg.sender].justification = _justification;
        publications[_publicationId].votation.votes[msg.sender].value = _vote;
    }

    function hashStruct(uint256 _publicationId, VoteValue _vote) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                REVEAL_VOTE_TYPEHASH,
                _publicationId,
                _vote,
                publications[_publicationId].votation.votes[msg.sender].nonce - 1
            )
        );
    }

    function timeToFinishCommitPhase(uint256 _publicationId) public view returns (uint256) {
        uint256 publishDate = publications[_publicationId].publishDate;
        uint256 phaseDuration = topics[publications[_publicationId].topicId].commitPhaseDuration;
        return publishDate + phaseDuration >= block.timestamp ? 0 : block.timestamp - (publishDate + phaseDuration);
    }

    function timeToFinishRevealPhase(uint256 _publicationId) public view returns (uint256) {
        uint256 publishDate = publications[_publicationId].publishDate;
        uint256 phaseDuration = topics[publications[_publicationId].topicId].revealPhaseDuration;
        return publishDate + phaseDuration >= block.timestamp ? 0 : block.timestamp - (publishDate + phaseDuration);
    }

    function setJurors(uint256 _publicationId) internal {
        uint256[] memory randoms = rng.getRandomNumbers(votingJurorsQuantity);
        for (uint256 i = 0; i < votingJurorsQuantity; i++) {
            // topics[publications[_publicationId].topicId].jurors[randoms[i]];
            publications[_publicationId].votation.jurors[address(this)] = true;
        }
    }
}
