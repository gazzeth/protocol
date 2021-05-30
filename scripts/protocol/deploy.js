async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contract with the account:", deployer.address);
    const Protocol = await ethers.getContractFactory("Protocol");
    const minutes = 60;
    const eighteenDecimalsTokenUnit = 10 ** 18;
    const gazzeth = '0x718ef0A3B144C4e40f8052e52b3C8Db690A17ce0';
    const dai = '0x1038b262c3a786713def6797ad9cbc5fc20439e2';
    const proofOfHumanity = '0x9b1590A4D36255b3b18Bb681062FD159f809009f';
    const rng = '0xE2F0263c02aCC09DCf21EcC8CA4E16CB6E3FA389';
    const minTopicJurorsQuantity = '10';
    const votingJurorsQuantity = '5';
    const defaultPriceToPublish = (3 * eighteenDecimalsTokenUnit).toString();
    const defaultPriceToBeJuror = (2 * eighteenDecimalsTokenUnit).toString();
    const defaultAuthorReward = eighteenDecimalsTokenUnit.toString();
    const defaultJurorReward = eighteenDecimalsTokenUnit.toString();
    const defaultCommitDuration = (10 * minutes).toString();
    const defaultRevealDuration = (10 * minutes).toString(); 
    const protocol = await Protocol.deploy(
        gazzeth,
        dai,
        proofOfHumanity,
        rng,
        minTopicJurorsQuantity,
        votingJurorsQuantity,
        defaultPriceToPublish,
        defaultPriceToBeJuror,
        defaultAuthorReward,
        defaultJurorReward,
        defaultCommitDuration,
        defaultRevealDuration
    );
    console.log("Contract address:", protocol.address);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });