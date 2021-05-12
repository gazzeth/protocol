// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/drafts/EIP712.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./interfaces/IDai.sol";
import "./interfaces/IProofOfHumanity.sol";
import "./Gazzeth.sol";

contract Protocol is EIP712 {

    using SafeMath for uint256;
    using Counters for Counters.Counter;

    modifier onlyExistentPublications(uint256 _publicationId) {
        require(_publicationId < nextPublicationId, "Publication does not exist");
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
        Counters.Counter nonce;
        VoteValue value;
        bytes32 commitment;
        string justification;
    }

    struct Votation {
        mapping (address => bool) jurors;
        mapping (address => Vote) votes;
    }

    struct Publication {
        string rebuiltCommitment;
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
        uint256 voteCommitmentDeadline;
        uint256 voteRevealDeadline;
        mapping (address => bool) jurors;
        uint256 jurorQuantity;
    }

    Gazzeth gazzeth;
    IDai dai;
    IProofOfHumanity proofOfHumanity;
    uint256 minTopicJurorsQuantity;
    uint256 votingJurorsQuantity;
    uint256 nextPublicationId;
    mapping (uint256 => Publication) publications;
    mapping (uint256 => Topic) topics;

    constructor(
        Gazzeth _gazzeth,
        IDai _dai,
        IProofOfHumanity _proofOfHumanity,
        uint256 _minTopicJurorsQuantity,
        uint256 _votingJurorsQuantity
    ) EIP712("Protocol", "1") {
        gazzeth = _gazzeth;
        dai = _dai;
        proofOfHumanity = _proofOfHumanity;
        minTopicJurorsQuantity = _minTopicJurorsQuantity;
        votingJurorsQuantity = _votingJurorsQuantity;
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
        Publication storage publication = publications[nextPublicationId];
        publication.rebuiltCommitment = _publicationHash;
        publication.author = msg.sender;
        publication.publishDate = block.timestamp;
        publication.topicId = _topicId;
        // publication.votation.jurors = chooseJurors(_topic);
        dai.permit(msg.sender, address(this), _nonce, _expiry, true, _v, _r, _s);
        dai.transferFrom(msg.sender, address(this), topics[_topicId].publishPrice);
        return nextPublicationId++;
    }

    function commitVote(
        uint256 _publicationId, bytes32 _commitment
    ) external onlyExistentPublications(_publicationId) onlyPublicationJurors(_publicationId) {
        uint256 publishDate = publications[_publicationId].publishDate;
        uint256 commitmentDeadline = topics[publications[_publicationId].topicId].voteCommitmentDeadline;
        require(publishDate + commitmentDeadline <= block.timestamp, "Vote commitment phase has already finished");
        publications[_publicationId].votation.votes[msg.sender].commitment = _commitment;
        publications[_publicationId].votation.votes[msg.sender].nonce.increment();
    }

    function revealVote(
        uint256 _publicationId, VoteValue _vote, string calldata _justification, uint8 _v, bytes32 _r, bytes32 _s
    ) external onlyExistentPublications(_publicationId) onlyPublicationJurors(_publicationId) {
        uint256 publishDate = publications[_publicationId].publishDate;
        uint256 commitmentDeadline = topics[publications[_publicationId].topicId].voteCommitmentDeadline;
        uint256 revealDeadline = topics[publications[_publicationId].topicId].voteRevealDeadline;
        // TODO: Even reverting, I think vote value is now public on etherscan. Penalize DAI deposit instead of reverting?
        require(publishDate + commitmentDeadline >= block.timestamp, "Vote commitment phase has not finished yet");
        require(publications[_publicationId].votation.votes[msg.sender].nonce.current() > 0, "Missing vote commitment");
        require(publishDate + revealDeadline <= block.timestamp, "Vote commitment phase has not finished yet");
        bytes32 hashStruct = keccak256(
            abi.encode(
                keccak256("RevealVote(uint256 publicationId,VoteValue vote,uint256 nonce)"),
                _publicationId,
                _vote,
                publications[_publicationId].votation.votes[msg.sender].nonce.current() - 1
            )
        );
        bytes32 rebuiltCommitment = _hashTypedDataV4(hashStruct);
        bytes32 commitment = publications[_publicationId].votation.votes[msg.sender].commitment;
        require(commitment == rebuiltCommitment, "Invalid vote reveal: revealed values do not match commitment");
        address signer = ECDSA.recover(rebuiltCommitment, _v, _r, _s);
        require(signer == msg.sender, "Invalid vote reveal: signature authenticity");
        publications[_publicationId].votation.votes[msg.sender].justification = _justification;
    }

    function getCurrentVoteCommitmentNonce(address _juror, uint256 _publicationId) external view returns (uint256) {
        return publications[_publicationId].votation.votes[_juror].nonce.current();
    }
}
