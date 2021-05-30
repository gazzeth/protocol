async function main() {
    const [sender] = await ethers.getSigners();
    console.log("Calling contract with the account:", sender.address);
    const Protocol = await ethers.getContractFactory("Protocol");
    const protocolAddress = '0xFa69eEf3065143ef233aA25f02beAA96d3B8BA99';
    const protocol = Protocol.attach(protocolAddress);
    const topicId = 'Worldwide/Ethereum/Airdrops';
    const times = '0';
    const zeroByte32 = '0x0000000000000000000000000000000000000000000000000000000000000000';
    const transaction = await protocol.subscribeAsJuror(topicId, times, '0', '0', '0', zeroByte32, zeroByte32);
    console.log("Transaction:", transaction);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
