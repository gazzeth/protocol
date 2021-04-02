// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import { Gazzeth } from "./Gazzeth.sol";

contract Protocol {

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
        bytes32 commitment;
        VoteValue value;
        string justification;
    }

    struct Votation {
        address[] jurors;
        mapping (address => Vote) votes;
    }

    struct Publication {
        uint256 id;
        string hash;
        address author;
        string topic;
        uint publishDate;
        Votation votation;
    }

    uint256 minimumTopicJurorsQuantity;
    uint256 votingJurorsQuantity;
    uint256 nextPublicationId;
    mapping (string => address[]) topicJurors;
    mapping (address => string[]) jurorTopics;
    mapping (uint256 => Publication) publications;
    Gazzeth gazzeth;

    constructor(Gazzeth _gazzeth, uint256 _minimumTopicJurorsQuantity, uint256 _votingJurorsQuantity) {
        gazzeth = _gazzeth;
        minimumTopicJurorsQuantity = _minimumTopicJurorsQuantity;
        votingJurorsQuantity = _votingJurorsQuantity;
    }

    function publish(string calldata _hash, string calldata _topic) external returns (uint256) {
        // require(check for msg.sender sufficient GZT); 
        require(topicJurors[_topic].length >= minimumTopicJurorsQuantity, "Insuficient jurors subscribed to the topic");
        Publication storage publication = publications[nextPublicationId];
        publication.id = nextPublicationId;
        publication.hash = _hash;
        publication.author = msg.sender;
        publication.publishDate = block.timestamp;
        publication.topic = _topic;
        publication.votation.jurors = chooseJurors(_topic);
        // lock GZT
        return nextPublicationId++;
    }

    function commitVote(
        uint256 _publicationId, bytes32 _commitment
    ) external onlyExistentPublications(_publicationId) onlyPublicationJurors(_publicationId) {
        // require(time for commitment phase has not finished);
        publications[_publicationId].votation.votes[msg.sender].commitment = _commitment;
    }

    function revealVote(
        uint256 _publicationId, VoteValue _voteValue, bytes32 _secret, string calldata _justification
    ) external onlyExistentPublications(_publicationId) onlyPublicationJurors(_publicationId) {
        // require(time for reveal phase has not finished);
        bytes32 rebuiltCommitment = buildCommitment(_voteValue, _secret);
        require(
            rebuiltCommitment == publications[_publicationId].votation.votes[msg.sender].commitment,
            "Reveal didn't match commitment"
        );
        publications[_publicationId].votation.votes[msg.sender].justification = _justification;
    }

    function chooseJurors(string calldata _topic) internal pure returns (address[] memory) {
        // Chose jurors from topic randomly, mark as "locked" part of their GZT
    }

    function addressIsJurorInPublication(address _addressToValidate, uint256 _publicationId) public view returns (bool) {
        for (uint8 i = 0; i < publications[_publicationId].votation.jurors.length; i++) {
            if (publications[_publicationId].votation.jurors[i] == _addressToValidate) {
                return true;
            }
        }
        return false;
    }

    function buildCommitment(VoteValue _voteValue, bytes32 _secret) internal view returns (bytes32) {
        // return keccak256(concatStrings(voteValueToString(voteValue), string(secret)));
    }

    function subscribeAsJurorForTopic(string calldata _topic) external {
        // Subscribe msg.sender to the given topic. Lock his GZT
    }

    function unsubscribeAsJurorForTopic(string calldata _topic) external {
        // Unsubscribe msg.sender to the given topic. Unlock his GZT
    }
}
