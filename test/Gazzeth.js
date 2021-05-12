const { expect } = require("chai");

describe("Gazzeth token contract", function() {

    describe("Gazzeth from clean deploy", async function() {

        let Gazzeth;
        let gazzeth;
        let owner;
        let protocolContract;
        let nonOwner;

        beforeEach(async function() {
            [owner, nonOwner, protocolContract, ...addresses] = await ethers.getSigners();
            Gazzeth = await ethers.getContractFactory("Gazzeth");
            gazzeth = await Gazzeth.deploy();
        });

        it("Deployment total supply must be zero", async function() {
            expect(await gazzeth.totalSupply()).to.equal(0);
        });

        it("Non owner account can't set protocol address", async function() {
            await expect(
                gazzeth.connect(nonOwner).setProtocolContractAddress(protocolContract.address)
            ).to.be.revertedWith("Only owner can call this function");
        });

        it("Owner can set protocol address but only once", async function() {
            gazzeth.setProtocolContractAddress(protocolContract.address)
            await expect(
                gazzeth.setProtocolContractAddress(protocolContract.address)
            ).to.be.revertedWith("Protocol contract address already set");
        });
    });

    describe("Gazzeth when owner has balance greater than zero", async function() {

        let Gazzeth;
        let gazzeth;
        let owner;
        let protocolContract;
        let other;
        const quantityToMint = 10000;

        beforeEach(async function() {
            [owner, other, protocolContract, ...addresses] = await ethers.getSigners();
            Gazzeth = await ethers.getContractFactory("Gazzeth");
            gazzeth = await Gazzeth.deploy();
            gazzeth.setProtocolContractAddress(protocolContract.address)
            await gazzeth.connect(protocolContract).mint(owner.address, quantityToMint);
        });

        it("When protocol mints tokens then minted must match supply and balance", async function() {
            expect(await gazzeth.totalSupply()).to.equal(quantityToMint);
            expect(await gazzeth.balanceOf(owner.address)).to.equal(quantityToMint);
        });

        it("When protocol burn tokens then minted must match supply and balance", async function() {
            const quantityToBurn = 6900;
            expect(quantityToBurn < quantityToMint);
            await gazzeth.connect(protocolContract).burn(owner.address, quantityToBurn);
            expect(await gazzeth.balanceOf(owner.address)).to.equal(quantityToMint - quantityToBurn);
        });
    });
});
