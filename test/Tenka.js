const { expect } = require("chai");
const { ethers } = require("hardhat");
const { MerkleTree } = require("merkletreejs");
const keccak256 = require("keccak256");

describe("TenKa", function () {
    async function deployTenKaFixture() {
        const [owner, otherAccount, anotherAccount] = await ethers.getSigners();
        const TenKa = await ethers.getContractFactory("TenKa");
        const tenKa = await TenKa.deploy();
        await tenKa.deployed();

        return { tenKa, owner, otherAccount, anotherAccount };
    }

    describe("Deployment", function () {
        it("Should set the right owner", async function () {
            const { tenKa, owner } = await deployTenKaFixture();
            expect(await tenKa.owner()).to.equal(owner.address);
        });
    });

    describe("Minting", function () {
        it("Should allow owner to airdrop tokens", async function () {
            const { tenKa, owner, otherAccount } = await deployTenKaFixture();
            await tenKa.airdrop(1, otherAccount.address);
            expect(await tenKa.balanceOf(otherAccount.address)).to.equal(1);
        });

        it("Should revert if non-owner tries to airdrop", async function () {
            const { tenKa, otherAccount } = await deployTenKaFixture();
            await expect(tenKa.connect(otherAccount).airdrop(1, otherAccount.address))
                .to.be.reverted;
        });


        it("Should allow whitelist minting with valid proof", async function () {
            const { tenKa, owner, otherAccount } = await deployTenKaFixture();
            const addresses = [owner.address, otherAccount.address];
            const leafNodes = addresses.map((addr) => keccak256(addr));
            const merkleTree = new MerkleTree(leafNodes, keccak256, { sortPairs: true });
            const merkleRoot = merkleTree.getRoot();
            await tenKa.setMerkleRoot(merkleRoot);
            await tenKa.setWhitelistMintEnabled(true);

            const proof = merkleTree.getHexProof(keccak256(otherAccount.address));
            await tenKa.connect(otherAccount).whitelistMint(1, proof, { value: ethers.utils.parseEther("1") });

            expect(await tenKa.balanceOf(otherAccount.address)).to.equal(1);
        });

        it("Should revert whitelist minting with invalid proof", async function () {
            const { tenKa, otherAccount } = await deployTenKaFixture();
            await tenKa.setWhitelistMintEnabled(true);
            const invalidProof = [];
            await expect(
                tenKa.connect(otherAccount).whitelistMint(1, invalidProof, { value: ethers.utils.parseEther("1") })
            ).to.be.revertedWith("Invalid proof!");
        });

        it("Should revert whitelist minting with invalid proof", async function () {
            const { tenKa, otherAccount } = await deployTenKaFixture();
            await tenKa.setWhitelistMintEnabled(true);
            const invalidProof = [];
            await expect(tenKa.connect(otherAccount).whitelistMint(1, invalidProof, { value: ethers.utils.parseEther("1") }))
                .to.be.revertedWith("Invalid proof!");
        });

        it("Should allow public minting", async function () {
            const { tenKa, otherAccount } = await deployTenKaFixture();
            await tenKa.setPublicMintEnabled(true);
            await tenKa.connect(otherAccount).mint(1, { value: ethers.utils.parseEther("1") });

            expect(await tenKa.balanceOf(otherAccount.address)).to.equal(1);
        });
    });


    describe("Royalty Info", function () {
        it("Should allow owner to set royalty info", async function () {
            const { tenKa, owner } = await deployTenKaFixture();
            await tenKa.setDefaultRoyalty(owner.address, 1000); // Setting 10% royalty

            const [receiver, amount] = await tenKa.royaltyInfo(1, ethers.utils.parseEther("1"));
            expect(receiver).to.equal(owner.address);
            expect(amount).to.equal(ethers.utils.parseEther("0.1"));
        });
    });


    describe("Metadata", function () {
        it("Should return the correct base URI", async function () {
            const { tenKa, owner } = await deployTenKaFixture();
            await tenKa.setUriPrefix("https://example.com/");
            await tenKa.setRevealed(true);

            await tenKa.airdrop(1, owner.address); // Mint a token to check URI
            const tokenURI = await tenKa.tokenURI(0);
            expect(tokenURI).to.equal("https://example.com/0");
        });

        it("Should return the hidden metadata URI when not revealed", async function () {
            const { tenKa, owner } = await deployTenKaFixture();
            await tenKa.setHiddenMetadataUri("https://example.com/hidden");

            await tenKa.airdrop(1, owner.address);

            const tokenURI = await tenKa.tokenURI(0); // Checking URI before minting any tokens
            expect(tokenURI).to.equal("https://example.com/hidden");
        });
    });


    describe("Operator Filtering", function () {
        it("Should allow owner to approve operator", async function () {
            const { tenKa, owner, otherAccount } = await deployTenKaFixture();
            await tenKa.airdrop(1, owner.address); // Ensure token exists
            await tenKa.approve(otherAccount.address, 0);

            expect(await tenKa.getApproved(0)).to.equal(otherAccount.address);
        });

        it("Should allow owner to set approval for all", async function () {
            const { tenKa, owner, otherAccount } = await deployTenKaFixture();
            await tenKa.setApprovalForAll(otherAccount.address, true);

            expect(await tenKa.isApprovedForAll(owner.address, otherAccount.address)).to.equal(true);
        });

        it("Should allow operator to transfer token", async function () {
            const { tenKa, owner, otherAccount } = await deployTenKaFixture();
            await tenKa.airdrop(1, owner.address);
            await tenKa.setApprovalForAll(otherAccount.address, true);

            await tenKa.connect(otherAccount).transferFrom(owner.address, otherAccount.address, 0);

            expect(await tenKa.ownerOf(0)).to.equal(otherAccount.address);
        });

        it("Should revert transfer by non-operator", async function () {
            const { tenKa, owner, otherAccount, anotherAccount } = await deployTenKaFixture();
            await tenKa.airdrop(1, owner.address);

            await expect(
                tenKa.connect(anotherAccount).transferFrom(owner.address, anotherAccount.address, 0)
            ).to.be.reverted;
        });

    });

    describe("Withdraw", function () {
        it("Should allow owner to withdraw funds", async function () {
            const { tenKa, owner } = await deployTenKaFixture();
            await tenKa.setPublicMintEnabled(true);
            await tenKa.mint(1, { value: ethers.utils.parseEther("1") });

            const ownerBalanceBefore = await ethers.provider.getBalance(owner.address);
            const tx = await tenKa.withdraw();
            const receipt = await tx.wait();

            const gasUsed = receipt.gasUsed.mul(receipt.effectiveGasPrice);
            const txCost = await tx.gasPrice.mul(receipt.cumulativeGasUsed);
            const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);

            // Calculamos el balance esperado del propietario después de retirar fondos
            const expectedBalance = ownerBalanceBefore
                .sub(txCost) // Restamos el costo total de la transacción
                .add(ethers.utils.parseEther("1")); // Sumamos el valor de Ether depositado

            // Verificamos que el balance actual del propietario sea igual al balance esperado
            expect(ownerBalanceAfter).to.equal(expectedBalance);
        });

        it("Should revert withdraw by non-owner", async function () {
            const { tenKa, otherAccount } = await deployTenKaFixture();
            await expect(tenKa.connect(otherAccount).withdraw()).to.be.reverted;
        });
    });
});