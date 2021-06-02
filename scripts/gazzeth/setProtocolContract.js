async function main() {
    const [sender] = await ethers.getSigners();
    console.log("Calling contract with the account:", sender.address);
    const Gazzeth = await ethers.getContractFactory("Gazzeth");
    const gazzethAddress = '0x6A68F71e0469464B0C1D8A2Eb864a0486f3166Cf';
    const gazzeth = Gazzeth.attach(gazzethAddress);
    const protocolAddress = '0x92Fba6413071183583a1d6125656D04437b1320f';
    const transaction = await gazzeth.setProtocolContractAddress(protocolAddress);
    console.log("Transaction:", transaction);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
