async function main() {
    const [sender] = await ethers.getSigners();
    console.log("Calling contract with the account:", sender.address);
    const Gazzeth = await ethers.getContractFactory("Gazzeth");
    const gazzethAddress = '0x718ef0A3B144C4e40f8052e52b3C8Db690A17ce0';
    const gazzeth = Gazzeth.attach(gazzethAddress);
    const protocolAddress = '0xFa69eEf3065143ef233aA25f02beAA96d3B8BA99';
    const transaction = await gazzeth.setProtocolContractAddress(protocolAddress);
    console.log("Transaction:", transaction);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
