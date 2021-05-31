// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/drafts/EIP712.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IDai.sol";
import "./interfaces/IProofOfHumanity.sol";
import "./interfaces/IRng.sol";
import "./Gazzeth.sol";

contract Protocol is EIP712 {

    using SafeMath for uint256;

    modifier onlyExistentPublications(uint256 _publicationId) {
        require(_publicationId < publicationId, "Publication does not exist");
        _;
    }

    modifier onlyPublicationJurors(uint256 _publicationId) {
        require(votings[_publicationId].isJuror[msg.sender], "You are not a juror for this publication");
        _;
    }

    event TopicCreation(
        string indexed _topicId,
        address indexed _founder,
        uint256 _priceToPublish,
        uint256 _priceToBeJuror,
        uint256 _authorReward,
        uint256 _jurorReward,
        uint256 _commitPhaseDuration,
        uint256 _revealPhaseDuration
    );

    event JurorSubscription(address indexed _juror, string indexed _topicId, uint256 _times);

    event PublicationSubmission(
        uint256 indexed _publicationId,
        address indexed _author,
        string indexed _topicId,
        address[] _jurors,
        string _hash,
        uint256 _publishDate
    );

    event VoteCommitment(address indexed _juror, uint256 indexed _publicationId, bytes32 _commitment);

    event VoteReveal(
        address indexed _juror,
        uint256 indexed _publicationId,
        uint256 indexed _voteValue,
        string _justification,
        uint256[] _voteCounters,
        uint256 _winningVote
    );

    event Withdrawal(uint256 indexed _publicationId);

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

    struct Voting {
        bool withdrawn;
        address[] jurors;
        uint256[] voteCounters;
        uint256 maxVoteCount;
        VoteValue winningVote;
        mapping (address => bool) isJuror;
        mapping (address => bool) isPenalized;
        mapping (address => Vote) votes;
    }

    struct Publication {
        string hash;
        address author;
        string topicId;
        uint256 publishDate;
    }

    struct Topic {
        bool created;
        bool closed;
        uint256 priceToPublish;
        uint256 priceToBeJuror;
        uint256 authorReward;
        uint256 jurorReward;
        uint256 commitPhaseDuration;
        uint256 revealPhaseDuration;
        uint256 jurorQuantity;
        address[] selectableJurors;
        mapping (address => uint256) jurorTimes;
        mapping (address => uint256) jurorSelectedTimes;
    }

    bytes32 immutable public REVEAL_VOTE_TYPEHASH;
    uint256 immutable public MIN_TOPIC_JURORS_QTY;
    uint256 immutable public VOTING_JURORS_QTY;
    uint256 immutable public DEFAULT_PRICE_TO_PUBLISH;
    uint256 immutable public DEFAULT_PRICE_TO_BE_JUROR;
    uint256 immutable public DEFAULT_AUTHOR_REWARD;
    uint256 immutable public DEFAULT_JUROR_REWARD;
    uint256 immutable public DEFAULT_COMMIT_DURATION;
    uint256 immutable public DEFAULT_REVEAL_DURATION;

    Gazzeth public gazzeth;
    IDai public dai;
    IProofOfHumanity public proofOfHumanity;
    IRng public rng;
    uint256 public publicationId;
    uint256 public protocolDaiBalance;
    mapping (string => Topic) public topics;
    mapping (uint256 => Publication) public publications;
    mapping (uint256 => Voting) public votings;

    /**
     * @dev Constructor of the Gazzeth Protocol contract.
     * @param _gazzeth Address of Gazzeth ERC20 token contract.
     * @param _dai Address of DAI ERC20 token contract.
     * @param _proofOfHumanity Address of Proof of Humanity contract.
     * @param _rng Address of a Random Number Generator contract.
     * @param _minTopicJurorsQuantity Minimum selectable jurors needed in a topic to publish.
     * @param _votingJurorsQuantity Number of jurors to be selected for voting a publication.
     * @param _defaultPriceToPublish Default price in DAI for publishing in a topic.
     * @param _defaultPriceToBeJuror Default price in DAI for subscribing one time as juror in a topic.
     * @param _defaultAuthorReward Default reward price in DAI for author.
     * @param _defaultJurorReward Default reward price in DAI for juror.
     * @param _defaultCommitDuration Default voting commit phase duration in seconds.
     * @param _defaultRevealDuration Default voting reveal phase duration in seconds.
     */
    constructor(
        Gazzeth _gazzeth,
        IDai _dai,
        IProofOfHumanity _proofOfHumanity,
        IRng _rng,
        uint256 _minTopicJurorsQuantity,
        uint256 _votingJurorsQuantity,
        uint256 _defaultPriceToPublish,
        uint256 _defaultPriceToBeJuror,
        uint256 _defaultAuthorReward,
        uint256 _defaultJurorReward,
        uint256 _defaultCommitDuration,
        uint256 _defaultRevealDuration
    ) EIP712("Protocol", "1") {
        gazzeth = _gazzeth;
        dai = _dai;
        proofOfHumanity = _proofOfHumanity;
        rng = _rng;
        MIN_TOPIC_JURORS_QTY = _minTopicJurorsQuantity;
        VOTING_JURORS_QTY = _votingJurorsQuantity;
        DEFAULT_PRICE_TO_PUBLISH = _defaultPriceToPublish;
        DEFAULT_PRICE_TO_BE_JUROR = _defaultPriceToBeJuror;
        DEFAULT_AUTHOR_REWARD = _defaultAuthorReward;
        DEFAULT_JUROR_REWARD = _defaultJurorReward;
        DEFAULT_REVEAL_DURATION = _defaultRevealDuration;
        DEFAULT_COMMIT_DURATION = _defaultCommitDuration;
        REVEAL_VOTE_TYPEHASH = keccak256("RevealVote(uint256 publicationId,VoteValue vote)");
    }

    /**
     * @dev Gets the time left to finish voting commit phase.
     * @param _publicationId The publication id corresponding to the publication where to obtain the deadlines.
     * @return An integer representing seconds left to finish voting commit phase.
     */
    function timeToFinishCommitPhase(uint256 _publicationId) public view returns (uint256) {
        return timeToDeadlineTimestamp(
            publications[_publicationId].publishDate + topics[publications[_publicationId].topicId].commitPhaseDuration
        );
    }

    /**
     * @dev Gets the time left to finish voting reveal phase.
     * @param _publicationId The publication id corresponding to the publication where to obtain the deadlines.
     * @return An integer representing seconds left to finish voting reveal phase.
     */
    function timeToFinishRevealPhase(uint256 _publicationId) public view returns (uint256) {
        return timeToDeadlineTimestamp(
            publications[_publicationId].publishDate
                + topics[publications[_publicationId].topicId].commitPhaseDuration
                + topics[publications[_publicationId].topicId].revealPhaseDuration
        );
    }

    /**
     * @dev Gets the next juror nonce available to use for commitment.
     * @param _juror The address of the juror corresponding to the nonce.
     * @param _publicationId The publication id corresponding to the nonce.
     * @return An integer representing the next nonce available for the given juror and publication.
     */
    function getCommitmentNonce(address _juror, uint256 _publicationId) external view returns (uint256) {
        return votings[_publicationId].votes[_juror].nonce;
    }

    /**
     * @dev Subscribes the sender as juror for the given topic. If topic does not extis, then creates it.
     * When adding times to the subscription DAI tokens are pulled from the juror balance.
     * To use as unsuscribe function, set times to zero. Also to create topic without subscribing to it.
     * @param _topicId The topic id to subscribe in.
     * @param _times The total times the juror is willing to be selected as juror simultaneously. Overrides the curent.
     * @param _nonce The nonce as defined in DAI permit function.
     * @param _expiry The expiry as defined in DAI permit function.
     * @param _v The v parameter of ECDSA signature as defined in EIP712.
     * @param _r The r parameter of ECDSA signature as defined in EIP712.
     * @param _s The s parameter of ECDSA signature as defined in EIP712.
     */
    function subscribeAsJuror(
        string calldata _topicId, uint256 _times, uint256 _nonce, uint256 _expiry, uint8 _v, bytes32 _r, bytes32 _s
    ) external {
        if (!topics[_topicId].created) {
            createTopic(_topicId);
        }
        if (topics[_topicId].jurorTimes[msg.sender] > _times) {
            decreaseJurorTimes(_topicId, _times);
        } else if (topics[_topicId].jurorTimes[msg.sender] < _times) {
            increaseJurorTimes(_topicId, _times, _nonce, _expiry, _v, _r, _s);
        }
        topics[_topicId].jurorTimes[msg.sender] = _times;
        JurorSubscription(msg.sender, _topicId, _times);
    }

    /**
     * @dev Sender publish a new publication in the given topic acting as the author. When publishing DAI tokens are 
     * pulled from the author balance, recovered later if the publication is voted as true by the selcted jurors.
     * @param _publicationHash The publication file hash.
     * @param _topicId The topic id where to publish.
     * @param _nonce The nonce as defined in DAI permit function.
     * @param _expiry The expiry as defined in DAI permit function.
     * @param _v The v parameter of ECDSA signature as defined in EIP712.
     * @param _r The r parameter of ECDSA signature as defined in EIP712.
     * @param _s The s parameter of ECDSA signature as defined in EIP712.
     * @return An integer indicating id assigned to the publication.
     */
    function publish(
        string calldata _publicationHash,
        string calldata _topicId,
        uint256 _nonce,
        uint256 _expiry,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (uint256) {
        require(topics[_topicId].created, "Unexistent topic");
        require(!topics[_topicId].closed, "Closed topic");
        require(
            topics[_topicId].selectableJurors.length >= MIN_TOPIC_JURORS_QTY,
            "Insuficient selectable jurors in the topic"
        );
        require(dai.balanceOf(msg.sender) >= topics[_topicId].priceToPublish, "Insuficient DAI to publish");
        Publication storage publication = publications[publicationId];
        publication.hash = _publicationHash;
        publication.author = msg.sender;
        publication.publishDate = block.timestamp;
        publication.topicId = _topicId;
        selectJurors(publicationId);
        votings[publicationId].voteCounters = [VOTING_JURORS_QTY, 0, 0, 0];
        dai.permit(msg.sender, address(this), _nonce, _expiry, true, _v, _r, _s);
        dai.transferFrom(msg.sender, address(this), topics[_topicId].priceToPublish);
        emit PublicationSubmission(
            publicationId, msg.sender, _topicId, votings[publicationId].jurors, _publicationHash, block.timestamp
        );
        return publicationId++;
    }

    /**
     * @dev Commits vote commitment for the given publication. First phase of the commit and reveal voting scheme.
     * @param _publicationId The publication id to vote for.
     * @param _commitment The commitment for this vote.
     * @param _nonce The nonce used to generate the given commitment.
     */
    function commitVote(
        uint256 _publicationId, bytes32 _commitment, uint256 _nonce
    ) external onlyExistentPublications(_publicationId) onlyPublicationJurors(_publicationId) {
        require(timeToFinishCommitPhase(_publicationId) > 0, "Vote commit phase has already finished");
        require(_nonce >= votings[_publicationId].votes[msg.sender].nonce, "Nonce must be greater than the last one");
        require(proofOfHumanity.isRegistered(msg.sender), "You must be registered in Proof of Humanity");
        votings[_publicationId].votes[msg.sender].commitment = _commitment;
        votings[_publicationId].votes[msg.sender].nonce = _nonce + 1;
        emit VoteCommitment(msg.sender, _publicationId, _commitment);
    }

    /**
     * @dev Reveals vote for the given publication. Second phase of the commit and reveal voting scheme.
     * The given parameters must match the last commitment performed by the juror.
     * @param _publicationId The publication id to vote for.
     * @param _vote The actual vote value.
     * @param _justification The justification for the given vote value.
     * @param _v The v parameter of ECDSA signature as defined in EIP712.
     * @param _r The r parameter of ECDSA signature as defined in EIP712.
     * @param _s The s parameter of ECDSA signature as defined in EIP712.
     * @return A boolean indicating if juror was penalized or not.
     */
    function revealVote(
        uint256 _publicationId, VoteValue _vote, string calldata _justification, uint8 _v, bytes32 _r, bytes32 _s
    ) external onlyExistentPublications(_publicationId) onlyPublicationJurors(_publicationId) returns (bool) {
        require(votings[_publicationId].votes[msg.sender].nonce > 0, "Missing vote commitment");
        require(timeToFinishRevealPhase(_publicationId) > 0, "Vote reveal phase has already finished");
        require(_vote != VoteValue.None, "Vote must be different than 'None'");
        require(votings[_publicationId].votes[msg.sender].value == VoteValue.None, "Reveal already done");
        require(!votings[_publicationId].isPenalized[msg.sender], "Penalized juror");
        require(
            votings[_publicationId].votes[msg.sender].commitment == keccak256(abi.encode(_v, _r, _s)),
            "Invalid vote reveal: revealed values do not match commitment"
        );
        require(
            ECDSA.recover(_hashTypedDataV4(hashStruct(_publicationId, _vote)), _v, _r, _s) == msg.sender,
            "Invalid vote reveal: invalid signature"
        );
        if (timeToFinishCommitPhase(_publicationId) > 0) {
            votings[_publicationId].isPenalized[msg.sender] = true;
        } else {
            require(proofOfHumanity.isRegistered(msg.sender), "You must be registered in Proof of Humanity");
            countVote(_publicationId, _vote, _justification);
        }
        emitVoteRevealEvent(_publicationId, _vote, _justification);
        return votings[_publicationId].isPenalized[msg.sender];
    }

    /**
     * @dev Withdraws rewards and confirms economic penalizations over the author and jurors after publication voting.
     * @param _publicationId The publication id where perform the withdrawal.
     */
    function withdrawRewards(uint256 _publicationId) external onlyExistentPublications(_publicationId) {
        require(timeToFinishRevealPhase(_publicationId) == 0, "Vote reveal phase has not finished yet");
        require(!votings[_publicationId].withdrawn, "Publication rewards already withdrawn");
        string memory topicId = publications[_publicationId].topicId;
        if (votings[_publicationId].winningVote == VoteValue.True) {
            dai.transferFrom(address(this), publications[_publicationId].author, topics[topicId].priceToPublish);
            gazzeth.mint(publications[_publicationId].author, topics[topicId].authorReward);
        }
        for (uint256 i = 0; i < votings[_publicationId].jurors.length; i++) {
            address juror = votings[_publicationId].jurors[i];
            if (jurorMustBeRewarded(_publicationId, juror)) {
                if (topics[topicId].jurorSelectedTimes[juror] == topics[topicId].jurorTimes[juror]) {
                    topics[topicId].selectableJurors.push(juror);
                }
                gazzeth.mint(juror, topics[topicId].jurorReward);
            } else {
                topics[topicId].jurorTimes[juror]--;
                // TODO: Take in account the line below when topic prices can be changed by governance
                protocolDaiBalance += topics[topicId].priceToBeJuror;
            }
            topics[topicId].jurorSelectedTimes[juror]--;
        }
        votings[_publicationId].withdrawn = true;
        emit Withdrawal(_publicationId);
    }

    /**
     * @dev Verifies if juror must be rewarded after voting. Must not be penalized and must voted the winning vote.
     * @param _publicationId The publication id where voting corresponds to.
     * @param _juror The juror address.
     * @return A boolean indicating if juror must be rewarded or not.
     */
    function jurorMustBeRewarded(uint256 _publicationId, address _juror) internal view returns (bool) {
        return !votings[_publicationId].isPenalized[_juror]
            && votings[_publicationId].votes[_juror].value != VoteValue.None 
            && votings[_publicationId].votes[_juror].value == votings[_publicationId].winningVote;
    }

    /**
     * @dev Generates the struct hash as defined in EIP712, used to rebuild commitment to perform reveal voting phase.
     * @param _publicationId The publication id where vote commitment corresponds to.
     * @param _vote The vote value revealed.
     * @return The struct hash according to EIP712 standard.
     */
    function hashStruct(uint256 _publicationId, VoteValue _vote) internal view returns (bytes32) {
        return keccak256(
            abi.encode(REVEAL_VOTE_TYPEHASH, _publicationId, _vote, votings[_publicationId].votes[msg.sender].nonce - 1)
        );
    }

    /**
     * @dev Counts the given vote for the given publication updating voting statuses.
     * @param _publicationId The publication id to vote for.
     * @param _vote The actual vote value.
     * @param _justification The justification for the given vote value.
     */
    function countVote(uint256 _publicationId, VoteValue _vote, string calldata _justification) internal {
        votings[_publicationId].voteCounters[uint256(VoteValue.None)]--;
        votings[_publicationId].voteCounters[uint256(_vote)]++;
        votings[_publicationId].votes[msg.sender].value = _vote;
        votings[_publicationId].votes[msg.sender].justification = _justification;
        if (votings[_publicationId].winningVote == _vote) {
            votings[_publicationId].maxVoteCount++;
        } else if (votings[_publicationId].voteCounters[uint256(_vote)] == votings[_publicationId].maxVoteCount) {
            votings[_publicationId].winningVote == VoteValue.None;
        } else if (votings[_publicationId].voteCounters[uint256(_vote)] > votings[_publicationId].maxVoteCount) {
            votings[_publicationId].winningVote == _vote;
            votings[_publicationId].maxVoteCount = votings[_publicationId].voteCounters[uint256(_vote)];
        }
    }

    /**
     * @dev Emits the VoteReveal event. Made as a separated function to avoid 'Stack too deep' error.
     * @param _publicationId The publication id to vote for.
     * @param _vote The actual vote value.
     * @param _justification The justification for the given vote value.
     */
    function emitVoteRevealEvent(uint256 _publicationId, VoteValue _vote, string calldata _justification) internal {
        emit VoteReveal(
            msg.sender,
            _publicationId,
            votings[_publicationId].isPenalized[msg.sender] ? uint256(VoteValue.None) : uint256(_vote),
            votings[_publicationId].isPenalized[msg.sender] ? "Penalized juror" : _justification,
            votings[_publicationId].voteCounters,
            uint256(votings[_publicationId].winningVote)
        );
    }

    /**
     * @dev Gets the time left to a given deadline.
     * @param _deadlineTimestamp The deadline where to obtain the time left.
     * @return An integer representing seconds left to reach the given deadline.
     */
    function timeToDeadlineTimestamp(uint256 _deadlineTimestamp) internal view returns (uint256) {
        return _deadlineTimestamp <= block.timestamp ? 0 : _deadlineTimestamp - block.timestamp;
    }

    /**
     * @dev Randomly selects the jurors for the given publication id.
     * @param _publicationId The publication id where jurors must be selected.
     */
    function selectJurors(uint256 _publicationId) internal {
        uint256[] memory randoms = rng.getRandomNumbers(VOTING_JURORS_QTY);
        string memory topicId = publications[_publicationId].topicId;
        uint256 selectableJurorsLength = topics[topicId].selectableJurors.length;
        for (uint256 i = 0; i < VOTING_JURORS_QTY; i++) {
            uint256 selectedJurorIndex = randoms[i] % selectableJurorsLength;
            address selectedJuror = topics[topicId].selectableJurors[selectedJurorIndex];
            topics[topicId].jurorSelectedTimes[selectedJuror]++;
            votings[_publicationId].jurors.push(selectedJuror);
            votings[_publicationId].isJuror[selectedJuror] = true;
            topics[topicId].selectableJurors[selectedJurorIndex] 
                = topics[topicId].selectableJurors[selectableJurorsLength - 1];
            if (topics[topicId].jurorSelectedTimes[selectedJuror] == topics[topicId].jurorTimes[selectedJuror]) {
                topics[topicId].selectableJurors[selectableJurorsLength - 1] 
                    = topics[topicId].selectableJurors[topics[topicId].selectableJurors.length - 1];
                topics[topicId].selectableJurors.pop();
            } else {
                topics[topicId].selectableJurors[selectableJurorsLength - 1] = selectedJuror;
            }
            selectableJurorsLength--;
        }
    }

    /**
     * @dev Creates a new topic with the given id and default values.
     * @param _topicId The id of the topic to create.
     */
    function createTopic(string calldata _topicId) internal {
        topics[_topicId].created = true;
        topics[_topicId].priceToPublish = DEFAULT_PRICE_TO_PUBLISH;
        topics[_topicId].priceToBeJuror = DEFAULT_PRICE_TO_BE_JUROR;
        topics[_topicId].authorReward = DEFAULT_AUTHOR_REWARD;
        topics[_topicId].jurorReward = DEFAULT_JUROR_REWARD;
        topics[_topicId].commitPhaseDuration = DEFAULT_COMMIT_DURATION;
        topics[_topicId].revealPhaseDuration = DEFAULT_REVEAL_DURATION;
        emit TopicCreation(
            _topicId,
            msg.sender,
            DEFAULT_PRICE_TO_PUBLISH,
            DEFAULT_PRICE_TO_BE_JUROR,
            DEFAULT_AUTHOR_REWARD,
            DEFAULT_JUROR_REWARD,
            DEFAULT_COMMIT_DURATION,
            DEFAULT_REVEAL_DURATION
        );
    }

    /**
     * @dev Decreases times as juror in the topic. Transfers the freed deposited DAI to the juror.
     * @param _topicId The topic id where to decrease juror times.
     * @param _times The total times the juror is willing to be selected as juror simultaneously. Overrides the curent.
     */
    function decreaseJurorTimes(string calldata _topicId, uint256 _times) internal {
        require(
            topics[_topicId].jurorSelectedTimes[msg.sender] <= _times,
            "You must finish some votings before decreasing times"
        );
        if (_times == 0 && topics[_topicId].jurorTimes[msg.sender] > 0) {
            topics[_topicId].jurorQuantity--;
            // This loop can be avoided maintaining a mapping from juror address to its index in selectableJurors array
            uint256 jurorIndex;
            for (uint256 i = 0; i < topics[_topicId].selectableJurors.length; i++) {
                if (topics[_topicId].selectableJurors[i] == msg.sender) {
                    jurorIndex = i;
                    break;
                }
            }
            address lastJuror = topics[_topicId].selectableJurors[topics[_topicId].selectableJurors.length - 1];
            topics[_topicId].selectableJurors[jurorIndex] = lastJuror;
            topics[_topicId].selectableJurors.pop();
        }
        // TODO: Lowering topic priceToBeJuror must transfer the DAI left over according to new price for each juror
        dai.transferFrom(
            address(this),
            msg.sender,
            (topics[_topicId].jurorTimes[msg.sender] - _times) * topics[_topicId].priceToBeJuror
        );
    }

    /**
     * @dev Increases times as juror in the topic. Pulls DAI as deposit from the juror.
     * @param _topicId The topic id where to decrease juror times.
     * @param _times The total times the juror is willing to be selected as juror simultaneously. Overrides the curent.
     * @param _nonce The nonce as defined in DAI permit function.
     * @param _expiry The expiry as defined in DAI permit function.
     * @param _v The v parameter of ECDSA signature as defined in EIP712.
     * @param _r The r parameter of ECDSA signature as defined in EIP712.
     * @param _s The s parameter of ECDSA signature as defined in EIP712.
     */
    function increaseJurorTimes(
        string calldata _topicId, uint256 _times, uint256 _nonce, uint256 _expiry, uint8 _v, bytes32 _r, bytes32 _s
    ) internal {
        require(proofOfHumanity.isRegistered(msg.sender), "To be a juror you must be registered on Proof of Humanity");
        uint256 daiToDeposit = (_times - topics[_topicId].jurorTimes[msg.sender]) * topics[_topicId].priceToBeJuror;
        require(dai.balanceOf(msg.sender) >= daiToDeposit, "Insuficient DAI to be juror that number of times");
        if (topics[_topicId].jurorTimes[msg.sender] == 0) {
            topics[_topicId].jurorQuantity++;
            topics[_topicId].selectableJurors.push(msg.sender);
        }
        dai.permit(msg.sender, address(this), _nonce, _expiry, true, _v, _r, _s);
        dai.transferFrom(msg.sender, address(this), daiToDeposit);
    }
}
