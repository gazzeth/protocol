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
        require(publications[_publicationId].voting.isJuror[msg.sender], "You are not a juror for this publication");
        _;
    }

    event JurorSubscription(address indexed _juror, string indexed _topic, uint256 _times);
    
    event VoteReveal(address indexed _juror, uint256 indexed _publicationId, uint256 indexed voteValue, string justification);

    event VoteCommitment(address indexed _juror, uint256 indexed _publicationId, bytes32 _commitment);

    event PublicationSubmission(
        uint256 indexed _publicationId,
        address indexed _author,
        string indexed _topicId,
        address[] _jurors,
        string _hash,
        uint256 _publishDate
    );

    event TopicCreation(
        string indexed _topicId,
        uint256 _priceToPublish,
        uint256 _priceToBeJuror,
        uint256 _authorReward,
        uint256 _jurorReward,
        uint256 _commitPhaseDuration,
        uint256 _revealPhaseDuration
    );

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
        uint256[] voteCounter;
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
        Voting voting;
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
    uint256 public daiInTreasury;
    mapping (uint256 => Publication) publications;
    mapping (string => Topic) topics;

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

    function getCommitmentNonce(address _juror, uint256 _publicationId) external view returns (uint256) {
        return publications[_publicationId].voting.votes[_juror].nonce;
    }

    function setAsJuror(
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
        require(topics[_topicId].selectableJurors.length >= MIN_TOPIC_JURORS_QTY, "Insuficient selectable jurors on the topic");
        require(dai.balanceOf(msg.sender) >= topics[_topicId].priceToPublish, "Insuficient DAI to publish");
        Publication storage publication = publications[publicationId];
        publication.hash = _publicationHash;
        publication.author = msg.sender;
        publication.publishDate = block.timestamp;
        publication.topicId = _topicId;
        selectJurors(publicationId);
        publication.voting.voteCounter = [VOTING_JURORS_QTY, 0, 0, 0];
        dai.permit(msg.sender, address(this), _nonce, _expiry, true, _v, _r, _s);
        dai.transferFrom(msg.sender, address(this), topics[_topicId].priceToPublish);
        emit PublicationSubmission(
            publicationId, msg.sender, _topicId, publications[publicationId].voting.jurors, _publicationHash, block.timestamp
        );
        return publicationId++;
    }

    function commitVote(
        uint256 _publicationId, bytes32 _commitment, uint256 _nonce
    ) external onlyExistentPublications(_publicationId) onlyPublicationJurors(_publicationId) {
        require(timeToFinishCommitPhase(_publicationId) > 0, "Vote commit phase has already finished");
        require(_nonce >= publications[_publicationId].voting.votes[msg.sender].nonce, "Nonce must be greater than the last one");
        if (!proofOfHumanity.isRegistered(msg.sender)) {
            // Encourage to unregister from topics until being registered on PoH again
            publications[_publicationId].voting.isPenalized[msg.sender] = true;
        }
        publications[_publicationId].voting.votes[msg.sender].commitment = _commitment;
        publications[_publicationId].voting.votes[msg.sender].nonce = _nonce + 1;
        emit VoteCommitment(msg.sender, _publicationId, _commitment);
    }

    function revealVote(
        uint256 _publicationId, VoteValue _vote, string calldata _justification, uint8 _v, bytes32 _r, bytes32 _s
    ) external onlyExistentPublications(_publicationId) onlyPublicationJurors(_publicationId) {
        require(publications[_publicationId].voting.votes[msg.sender].nonce > 0, "Missing vote commitment");
        require(timeToFinishRevealPhase(_publicationId) > 0, "Vote reveal phase has already finished");
        require(_vote != VoteValue.None, "Vote must be different than 'None'");
        require(
            publications[_publicationId].voting.votes[msg.sender].commitment == keccak256(abi.encode(_v, _r, _s)),
            "Invalid vote reveal: revealed values do not match commitment"
        );
        require(
            ECDSA.recover(_hashTypedDataV4(hashStruct(_publicationId, _vote)), _v, _r, _s) == msg.sender,
            "Invalid vote reveal: invalid signature"
        );
        if (timeToFinishCommitPhase(_publicationId) > 0 || !proofOfHumanity.isRegistered(msg.sender)) {
            publications[_publicationId].voting.isPenalized[msg.sender] = true;
        }
        uint256 voteInt = uint256(_vote);
        publications[_publicationId].voting.voteCounter[uint256(VoteValue.None)]--;
        publications[_publicationId].voting.voteCounter[voteInt]++;
        publications[_publicationId].voting.votes[msg.sender].value = _vote;
        publications[_publicationId].voting.votes[msg.sender].justification = _justification;
        if (publications[_publicationId].voting.winningVote == _vote) {
            publications[_publicationId].voting.maxVoteCount++;
        } else if (publications[_publicationId].voting.voteCounter[voteInt] == publications[_publicationId].voting.maxVoteCount) {
            publications[_publicationId].voting.winningVote == VoteValue.None;
        } else if (publications[_publicationId].voting.voteCounter[voteInt] > publications[_publicationId].voting.maxVoteCount) {
            publications[_publicationId].voting.winningVote == _vote;
            publications[_publicationId].voting.maxVoteCount = publications[_publicationId].voting.voteCounter[voteInt];
        }
        emit VoteReveal(msg.sender, _publicationId, uint256(_vote), _justification);
    }

    function withdrawRewards(uint256 _publicationId) external onlyExistentPublications(_publicationId) {
        require(timeToFinishRevealPhase(_publicationId) == 0, "Vote reveal phase has not finished yet");
        require(!publications[_publicationId].voting.withdrawn, "Publication rewards already withdrawn");
        string memory topicId = publications[_publicationId].topicId;
        if (publications[_publicationId].voting.winningVote == VoteValue.True) {
            dai.transferFrom(address(this), publications[_publicationId].author, topics[topicId].priceToPublish);
            gazzeth.mint(publications[_publicationId].author, topics[topicId].authorReward);
        }
        for (uint256 i = 0; i < publications[_publicationId].voting.jurors.length; i++) {
            address juror = publications[_publicationId].voting.jurors[i];
            if (jurorMustBeRewarded(_publicationId, juror)) {
                if (topics[topicId].jurorSelectedTimes[juror] == topics[topicId].jurorTimes[juror]) {
                    topics[topicId].selectableJurors.push(juror);
                }
                gazzeth.mint(juror, topics[topicId].jurorReward);
            } else {
                topics[topicId].jurorTimes[juror]--;
                // TODO: Take in account the line below when topic prices can be changed by governance
                daiInTreasury += topics[topicId].priceToBeJuror;
            }
            topics[topicId].jurorSelectedTimes[juror]--;
        }
        publications[_publicationId].voting.withdrawn = true;
    }

    function jurorMustBeRewarded(uint256 _publicationId, address _juror) internal view returns (bool) {
        return !publications[_publicationId].voting.isPenalized[_juror]
            && publications[_publicationId].voting.votes[_juror].value != VoteValue.None 
            && publications[_publicationId].voting.votes[_juror].value == publications[_publicationId].voting.winningVote;
    }

    function hashStruct(uint256 _publicationId, VoteValue _vote) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                REVEAL_VOTE_TYPEHASH,
                _publicationId,
                _vote,
                publications[_publicationId].voting.votes[msg.sender].nonce - 1
            )
        );
    }

    function selectJurors(uint256 _publicationId) internal {
        uint256[] memory randoms = rng.getRandomNumbers(VOTING_JURORS_QTY);
        string memory topicId = publications[_publicationId].topicId;
        uint256 selectableJurorsLength = topics[topicId].selectableJurors.length;
        for (uint256 i = 0; i < VOTING_JURORS_QTY; i++) {
            uint256 selectedJurorIndex = randoms[i] % selectableJurorsLength;
            address selectedJuror = topics[topicId].selectableJurors[selectedJurorIndex];
            topics[topicId].jurorSelectedTimes[selectedJuror]++;
            publications[_publicationId].voting.jurors.push(selectedJuror);
            publications[_publicationId].voting.isJuror[selectedJuror] = true;
            topics[topicId].selectableJurors[selectedJurorIndex] = topics[topicId].selectableJurors[selectableJurorsLength - 1];
            if (topics[topicId].jurorSelectedTimes[selectedJuror] == topics[topicId].jurorTimes[selectedJuror]) {
                uint256 lastIndex = topics[topicId].selectableJurors.length - 1;
                topics[topicId].selectableJurors[selectableJurorsLength - 1] = topics[topicId].selectableJurors[lastIndex];
                topics[topicId].selectableJurors.pop();
            } else {
                topics[topicId].selectableJurors[selectableJurorsLength - 1] = selectedJuror;
            }
            selectableJurorsLength--;
        }
    }

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
            DEFAULT_PRICE_TO_PUBLISH,
            DEFAULT_PRICE_TO_BE_JUROR,
            DEFAULT_AUTHOR_REWARD,
            DEFAULT_JUROR_REWARD,
            DEFAULT_COMMIT_DURATION,
            DEFAULT_REVEAL_DURATION
        );
    }

    function decreaseJurorTimes(string calldata _topicId, uint256 _times) internal {
        require(topics[_topicId].jurorSelectedTimes[msg.sender] <= _times, "You must finish some votings before decreasing times");
        if (_times == 0 && topics[_topicId].jurorTimes[msg.sender] > 0) {
            topics[_topicId].jurorQuantity--;
            // This loop could be avoided maintaining a mapping from juror address to its index in selectableJurors array
            uint256 selectableJurorsLength = topics[_topicId].selectableJurors.length;
            uint256 jurorIndex;
            for (uint256 i = 0; i < selectableJurorsLength; i++) {
                if (topics[_topicId].selectableJurors[i] == msg.sender) {
                    jurorIndex = i;
                    break;
                }
            }
            topics[_topicId].selectableJurors[jurorIndex] = topics[_topicId].selectableJurors[selectableJurorsLength - 1];
            topics[_topicId].selectableJurors.pop();
        }
        // TODO: Lowering topic priceToBeJuror must transfer the DAI left over according to new price for each juror
        dai.transferFrom(
            address(this), msg.sender, (topics[_topicId].jurorTimes[msg.sender] - _times) * topics[_topicId].priceToBeJuror
        );
    }

    function increaseJurorTimes(
        string calldata _topicId, uint256 _times, uint256 _nonce, uint256 _expiry, uint8 _v, bytes32 _r, bytes32 _s
    ) internal {
        require(proofOfHumanity.isRegistered(msg.sender), "To be a juror you must be registered on Proof of Humanity");
        require(
            dai.balanceOf(msg.sender) >= (_times - topics[_topicId].jurorTimes[msg.sender]) * topics[_topicId].priceToBeJuror,
            "Insuficient DAI to be juror that number of times"
        );
        if (topics[_topicId].jurorTimes[msg.sender] == 0) {
            topics[_topicId].jurorQuantity++;
        }
        dai.permit(msg.sender, address(this), _nonce, _expiry, true, _v, _r, _s);
        dai.transferFrom(
            msg.sender, address(this), (_times - topics[_topicId].jurorTimes[msg.sender]) * topics[_topicId].priceToBeJuror
        );
    }
}
