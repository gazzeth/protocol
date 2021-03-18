// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

contract Protocol {

    modifier onlyJurors(uint256 publicationId) {
        require(addressIsJurorInPublication(msg.sender, publicationId), "You must be a juror for the publication");
        _;
    }

    uint16 constant MINIMUM_TOPIC_JURORS_QUANTITY = 1000;
    uint8 constant VOTING_JURORS_QUANTITY = 10;

    struct Publication {
        uint256 id;
        string hash;
        uint publishDate;
        string topic;
    }

    enum VoteValue {
        None,
        True,
        False,
        Unqualified
    }
    
    struct Vote {
        address juror;
        VoteValue value;
        string justification;
    }

    struct Votation {
        uint256 publicationId;
        address[] jurors;
        // mapping (address => string) voteCommitments;
        // mapping (address => VoteValue) votes;
        uint8 trueVotes;
        uint8 falseVotes;
        uint8 unquialifiedVotes;
    }

    uint256 nextPublicationId;
    mapping (string => uint256) topicJurors;
    mapping (uint256 => Publication) publications;
    mapping (uint256 => Votation) votations;

    function publish(string calldata hash, string calldata topic) external returns (uint256) {
        // require(msg.sender); Check for sufficient GZT!
        require(topicJurors[topic] >= MINIMUM_TOPIC_JURORS_QUANTITY, "Insuficient jurors subscribed to the topic");
        address[] memory jurors = chooseJurors(topic);
        Publication memory publication = Publication(nextPublicationId, hash, block.timestamp, topic);
        Votation memory votation = Votation(nextPublicationId, jurors, 0, 0, 0);
        publications[nextPublicationId] = publication;
        votations[nextPublicationId] = votation;
        return nextPublicationId++;
    }

    function commitVote(uint256 publicationId, string calldata commitment) external onlyJurors(publicationId) {
        // Commits a secret vote
    }

    function revealVote(
        uint256 publicationId, VoteValue voteValue, string calldata secret, string calldata justification
    ) external onlyJurors(publicationId) {
        // Reveals a vote and attachs justification
    }

    function chooseJurors(string calldata topic) internal returns (address[] memory) {
        // Chose jurors from topic randomly, mark as "in use" part of their GZT
    }

    function addressIsJurorInPublication(address addressToValidate, uint256 publicationId) public view returns (bool) {
        for (uint8 i = 0; i < votations[publicationId].jurors.length; i++) {
            if (votations[publicationId].jurors[i] == addressToValidate) {
                return true;
            }
        }
        return false;
    }

    function subscribeAsJurorForTopic(string calldata topic) external {
        // Subscribe msg.sender to the given topic. Lock/Stake his GZT
    }

    function unsubscribeAsJurorForTopic(string calldata topic) external {
        // Unsubscribe msg.sender to the given topic. Unlock/Unstake his GZT
    }
}
