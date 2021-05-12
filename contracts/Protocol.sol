// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IDai.sol";
import "./interfaces/IProofOfHumanity.sol";
import "./Gazzeth.sol";

contract Protocol {

    using SafeMath for uint256;

    modifier onlyExistentPublications(uint256 publicationId) {
        require(publicationId < nextPublicationId, "Publication does not exist");
        _;
    }

    modifier onlyPublicationJurors(uint256 publicationId) {
        require(addressIsJurorInPublication(msg.sender, publicationId), "You are not a juror for this publication");
        _;
    }

    enum VoteValue {
        None,
        True,
        False,
        Unqualified
    }
    
    struct Vote {
        VoteValue value;
        string justification;
    }

    struct Votation {
        address[] jurors;
        mapping (address => Vote) votes;
    }

    struct Publication {
        string hash;
        address author;
        string topicId;
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
    ) {
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
        publication.id = nextPublicationId;
        publication.hash = _publicationHash;
        publication.author = msg.sender;
        publication.publishDate = block.timestamp;
        publication.topicId = _topicId;
        // publication.votation.jurors = chooseJurors(_topic);
        dai.permit(msg.sender, address(this), _nonce, _expiry, true, _v, _r, _s);
        dai.transferFrom(msg.sender, address(this), topics[_topicId].publishPrice);
        return nextPublicationId++;
    }
}
