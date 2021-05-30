async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contract with the account:", deployer.address);
    const Gazzeth = await ethers.getContractFactory("Gazzeth");
    const gazzeth = await Gazzeth.deploy();
    console.log("Contract address:", gazzeth.address);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
