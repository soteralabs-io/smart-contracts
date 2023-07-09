import { expect } from "chai";
import { BigNumber } from "ethers";
import { keccak256, solidityPack, solidityKeccak256, parseEther } from "ethers/lib/utils";
import { ethers, network } from "hardhat";
import { BeyondLand, BeyondLand__factory } from "../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

function now(): number {
  return Date.now() / 1000 | 0;
}

async function signMessage(signer: SignerWithAddress, address: string, maxLands: number): Promise<string> {
  let hash: string = solidityKeccak256(["address", "uint256"], [address, maxLands]);
  const sig = await signer.signMessage(ethers.utils.arrayify(hash));
  return sig;
}

async function setBlockTime(ts: number) {
  await time.increaseTo(ts);
}

describe("BeyondLand", function() {
  const provider = ethers.provider;

  let mintPrice: BigNumber;

  const maxClaimableLands = 1500;
  const maxPublicLands = 5000;
  const maxLands = 10_000;

  let maxMintPerAddress: number;

  let Land: BeyondLand__factory;
  let land: BeyondLand;

  let mintStartTime = now() + 35;
  let mintEndTime = mintStartTime + 90;

  beforeEach(async function() {
    Land = await ethers.getContractFactory("BeyondLand");
    land = await Land.deploy();
    await land.deployed();
    await land.setSupply(maxClaimableLands, maxPublicLands);

    mintPrice = await land.mintPrice();
    maxMintPerAddress = (await land.maxMintPerAddress()).toNumber();

    await land.setClaimableActive(true);
    await land.setMintStartTime(mintStartTime, mintEndTime);
  })

  describe("Claim", async function() {
    let owner: SignerWithAddress;
    let signer: SignerWithAddress;

    let buyer1: SignerWithAddress;
    let buyer1MaxLands = 4;

    let buyer2: SignerWithAddress;
    let buyer2MaxLands = 6;

    beforeEach(async function() {
      [owner, signer, buyer1, buyer2] = await ethers.getSigners();

      await land.setSigner(signer.address);
    })

    it("cannot claim when claimable is not started", async function() {
      await land.setClaimableActive(false);
      await (expect(land.connect(buyer1).claimLands(1, buyer1MaxLands,
        await signMessage(signer, buyer1.address, buyer1MaxLands),
      )).to.be.revertedWith("Mint not started"));
    });

    it("cannot claim if using invalid proof", async function() {
      const [owner, signer, , , nonBuyer] = await ethers.getSigners();
      await (expect(land.connect(buyer1).claimLands(
        1,
        maxLands,
        await signMessage(signer, buyer1.address, maxLands + 1)
      )).to.be.revertedWith("Invalid signature"));
      await (expect(land.connect(nonBuyer).claimLands(
        1,
        maxLands,
        await signMessage(signer, buyer1.address, maxLands),
      )).to.be.revertedWith("Invalid signature"));
    });

    it("claim with valid proof", async function() {
      await land.connect(buyer1).claimLands(
        1,
        buyer1MaxLands,
        await signMessage(signer, buyer1.address, buyer1MaxLands),
      );
      await land.connect(buyer1).claimLands(
        1,
        buyer1MaxLands,
        await signMessage(signer, buyer1.address, buyer1MaxLands),
      );
      expect(await land.ownerOf(1)).to.eq(buyer1.address);
      expect(await land.ownerOf(2)).to.eq(buyer1.address);
      expect(await land.balanceOf(buyer1.address)).to.eq(2);

      await land.connect(buyer2).claimLands(
        3,
        buyer2MaxLands,
        await signMessage(signer, buyer2.address, buyer2MaxLands),
      );
      await land.connect(buyer2).claimLands(
        2,
        buyer2MaxLands,
        await signMessage(signer, buyer2.address, buyer2MaxLands),
      );
      expect(await land.ownerOf(3)).to.eq(buyer2.address);
      expect(await land.ownerOf(4)).to.eq(buyer2.address);
      expect(await land.ownerOf(5)).to.eq(buyer2.address);
      expect(await land.ownerOf(6)).to.eq(buyer2.address);
      expect(await land.ownerOf(7)).to.eq(buyer2.address);
      expect(await land.balanceOf(buyer2.address)).to.eq(5);

      expect(await land.totalSupply()).to.eq(7);
    });

    it("cannot claim if max claimable lands per address exceeded", async function() {
      await land.connect(buyer1).claimLands(
        buyer1MaxLands,
        buyer1MaxLands,
        await signMessage(signer, buyer1.address, buyer1MaxLands),
      );
      await expect(
        land.connect(buyer1).claimLands(
          1,
          buyer1MaxLands,
          await signMessage(signer, buyer1.address, buyer1MaxLands),
        )
      ).to.be.revertedWith("Max claimable lands per address exceeded");

      await land.connect(buyer2).claimLands(
        buyer2MaxLands,
        buyer2MaxLands,
        await signMessage(signer, buyer2.address, buyer2MaxLands),
      );
      await expect(
        land.connect(buyer2).claimLands(
          2,
          buyer2MaxLands,
          await signMessage(signer, buyer2.address, buyer2MaxLands),
        )
      ).to.be.revertedWith("Max claimable lands per address exceeded");
    });
  });

  describe("Public", async function() {
    let owner: SignerWithAddress;
    let buyer1: SignerWithAddress;
    let buyer2: SignerWithAddress;

    before(async function() {
      await setBlockTime(mintStartTime);
    })

    beforeEach(async function() {
      [owner, buyer1, buyer2] = await ethers.getSigners();
    })

    it("cannot mint when public mint is not started", async function() {
      const [owner, buyer] = await ethers.getSigners();

      await land.setMintStartTime(0, 0);
      await (expect(land.connect(buyer).mintLands(1)).to.be.revertedWith("Mint not started"));

      await land.setMintStartTime(mintStartTime + mintEndTime + 1, 0);
      await (expect(land.connect(buyer).mintLands(1)).to.be.revertedWith("Mint not started"));
    });

    it("cannot mint if max lands per address exceeded", async function() {
      await land.connect(buyer1).mintLands(maxMintPerAddress, { value: mintPrice.mul(maxMintPerAddress) });
      await (expect(land.connect(buyer1).mintLands(1, { value: mintPrice })).to.be.revertedWith("Max lands per address exceeded"));
    });

    it("cannot mint if sending ether less than total value", async function() {
      await (expect(land.connect(buyer1).mintLands(2, { value: mintPrice.mul(1) })).to.be.revertedWith("Ether value sent is not correct"));
    });

    it("cannot mint 0 land", async function() {
      await (expect(land.connect(buyer1).mintLands(0, { value: mintPrice.mul(0) })).to.be.reverted);
    });

    it("mint with valid data", async function() {
      await land.connect(buyer1).mintLands(4, { value: mintPrice.mul(4) });
      expect(await land.balanceOf(buyer1.address)).to.eq(4);
    });
  });

  describe("Owner methods", async function() {
    let owner: SignerWithAddress;
    let signer: SignerWithAddress;
    let buyer1: SignerWithAddress;

    beforeEach(async function() {
      [owner, signer, buyer1] = await ethers.getSigners();
    })

    it("only owner can call setter functions", async function() {
      await (expect(land.connect(buyer1).reveal()).to.be.revertedWith("Ownable: caller is not the owner"));
      await (expect(land.connect(buyer1).setClaimableActive(false)).to.be.revertedWith("Ownable: caller is not the owner"));
      await (expect(land.connect(buyer1).setMintStartTime(now(), now() + 86400)).to.be.revertedWith("Ownable: caller is not the owner"));
      await (expect(land.connect(buyer1).setMaxMintPerAddress(2)).to.be.revertedWith("Ownable: caller is not the owner"));
      await (expect(land.connect(buyer1).withdraw(0)).to.be.revertedWith("Ownable: caller is not the owner"));
      await (expect(land.connect(buyer1).setSigner("0x6416d319fff28eBAdD47A669f5131D838FB5b716")).to.be.revertedWith("Ownable: caller is not the owner"));
      await (expect(land.connect(buyer1).setProvenanceHash("abc")).to.be.revertedWith("Ownable: caller is not the owner"));
      await (expect(land.connect(buyer1).setMintPrice(1)).to.be.revertedWith("Ownable: caller is not the owner"));
      await (expect(land.connect(buyer1).setSupply(1, 2)).to.be.revertedWith("Ownable: caller is not the owner"));
    });
  });

  describe("E2E", async function() {
    it("E2E", async function() {
      // prepare data
      const [
        owner,
        signer,
        claimableMinter1,
        claimableMinter2,
        claimableMinter3,
        claimableMinter4,
        claimableMinter5,
        publicMinter1,
        publicMinter2,
        publicMinter3,
        publicMinter4,
        publicMinter5,
        publicMinter6,
        publicMinter7,
      ] = await ethers.getSigners();

      land = await Land.deploy();
      await land.deployed();

      mintStartTime = (await time.latest()) + 600;
      mintEndTime = mintStartTime + 900;

      await land.setSigner(signer.address);
      await land.setClaimableActive(false);
      await land.setMintStartTime(mintStartTime, mintEndTime);
      await land.setSupply(318, 9)

      let currentTokenId = 1;
      let totalSupply = 0;
      let allTokenIds: Array<number> = [];

      const validateBalance = async (user: SignerWithAddress, numLands: number) => {
        const balance = await land.balanceOf(user.address);
        expect(balance).to.equal(numLands);

        const tokenIds = await land.tokensOf(user.address);
        expect(tokenIds.length).to.equal(balance.toNumber());

        for (let i = 0; i < tokenIds.length; i++) {
          const tokenId = tokenIds[i].toNumber();

          if (!allTokenIds.includes(tokenId)) {
            allTokenIds.push(tokenId);
            expect(tokenId).to.eq(currentTokenId);
            currentTokenId++;
          }

          expect(await land.ownerOf(tokenId)).to.eq(user.address);
        }

        expect(await land.totalSupply()).to.equal(allTokenIds.length);
      }

      const mustTransferNormally = async (user: SignerWithAddress) => {
        let tokenIds = await land.tokensOf(user.address);
        for (let i = 0; i < tokenIds.length; i++) {
          const tokenId = tokenIds[i];
          await land.connect(user).transferFrom(user.address, owner.address, tokenId);
          expect(await land.ownerOf(tokenId)).to.eq(owner.address);
        }
      }

      ///////////////// CLAIM ROUND ///////////////////////
      await land.setClaimableActive(true);

      // claimableMinter1 can mint 100 lands
      await land.connect(claimableMinter1).claimLands(
        100,
        500,
        await signMessage(signer, claimableMinter1.address, 500),
      );
      await validateBalance(claimableMinter1, 100);

      await land.connect(claimableMinter1).claimLands(
        200,
        500,
        await signMessage(signer, claimableMinter1.address, 500),
      );
      await validateBalance(claimableMinter1, 300);

      await mustTransferNormally(claimableMinter1);

      // claimableMinter2 can mint 10 lands
      await land.connect(claimableMinter2).claimLands(
        9,
        10,
        await signMessage(signer, claimableMinter2.address, 10),
      );
      await validateBalance(claimableMinter2, 9);

      await (expect(land.connect(claimableMinter2).claimLands(
        2,
        10,
        await signMessage(signer, claimableMinter2.address, 10),
      ))).to.be.revertedWith("Max claimable lands per address exceeded");

      await land.connect(claimableMinter2).claimLands(
        1,
        10,
        await signMessage(signer, claimableMinter2.address, 10),
      );
      await validateBalance(claimableMinter2, 10);

      await mustTransferNormally(claimableMinter2);

      // claimableMinter5 can mint 1 lands
      await land.connect(claimableMinter5).claimLands(
        1,
        1,
        await signMessage(signer, claimableMinter5.address, 1),
      );
      await validateBalance(claimableMinter5, 1);

      await (expect(land.connect(claimableMinter5).claimLands(
        3,
        3,
        await signMessage(signer, claimableMinter5.address, 3),
      ))).to.be.revertedWith("Max claimable lands per address exceeded");

      // claimableMinter5 can mint 2 more lands
      await land.connect(claimableMinter5).claimLands(
        2,
        3,
        await signMessage(signer, claimableMinter5.address, 3),
      );
      await validateBalance(claimableMinter5, 3);

      await (expect(land.connect(claimableMinter5).claimLands(
        1,
        3,
        await signMessage(signer, claimableMinter5.address, 3),
      ))).to.be.revertedWith("Max claimable lands per address exceeded");

      ///////////////// PUBLIC ROUND ///////////////////////
      await setBlockTime(mintStartTime);

      let totalLandsMinted = 0;

      await land.connect(publicMinter1).mintLands(
        maxMintPerAddress,
        { value: mintPrice.mul(maxMintPerAddress) }
      );

      await expect(land.connect(publicMinter1).mintLands(
        1,
        { value: mintPrice }
      )).to.be.revertedWith("Max lands per address exceeded");

      await validateBalance(publicMinter1, maxMintPerAddress);
      await mustTransferNormally(publicMinter1);

      expect(await land.totalLandsMinted()).to.equal(maxMintPerAddress);
      totalLandsMinted += maxMintPerAddress;

      await land.connect(publicMinter2).mintLands(
        maxMintPerAddress - 1,
        { value: mintPrice.mul(maxMintPerAddress - 1) }
      );
      await validateBalance(publicMinter2, maxMintPerAddress - 1);
      await mustTransferNormally(publicMinter2);

      expect(await land.totalLandsMinted()).to.equal(totalLandsMinted + maxMintPerAddress - 1);
      totalLandsMinted += maxMintPerAddress - 1;

      await mustTransferNormally(claimableMinter1);

      console.log("Total supply: ", (await land.totalSupply()).toNumber());

      await (expect(land.connect(publicMinter4).mintLands(
        3,
        {
          value: mintPrice.mul(3),
        }
      )).to.be.revertedWith("Max public lands exceeded"));

      await land.connect(publicMinter4).mintLands(
        2,
        {
          value: mintPrice.mul(2),
        }
      );
      await validateBalance(publicMinter4, 2);

      expect(await land.totalLandsMinted()).to.equal(totalLandsMinted + 2);
      totalLandsMinted += 2;

      // publicMinter3 cannnot mint, because max supply reached
      await (expect(land.connect(publicMinter3).mintLands(
        1,
        { value: mintPrice }
      ))).to.be.revertedWith("Max public lands exceeded");

      await setBlockTime(mintEndTime + 1);

      // cannot mint public anymore
      await expect(land.connect(publicMinter2).mintLands(
        9,
        { value: mintPrice.mul(9) }
      )).to.be.revertedWith("Mint not started");

      // but can claim normally
      await land.connect(claimableMinter3).claimLands(
        5,
        5,
        await signMessage(signer, claimableMinter3.address, 5),
      );
      await validateBalance(claimableMinter3, 5);

      expect(await land.totalLandsMinted()).to.equal(totalLandsMinted);

      await (expect(land.connect(claimableMinter4).claimLands(
        1,
        1,
        await signMessage(signer, claimableMinter4.address, 1),
      ))).to.be.revertedWith("Max claimable lands exceeded");

      // claim can transfer normally
      await mustTransferNormally(claimableMinter1);

      await land.setMintStartTime(await land.mintStartTime(), (await land.mintEndTime()).toNumber() + 90);
      await land.setSupply(318, 10);
      expect(await land.MAX_LANDS()).to.eq(328);
      expect(await land.MAX_PUBLIC_LANDS()).to.not.eq(totalLandsMinted);

      await land.connect(publicMinter6).mintLands(1, { value: mintPrice });
      await (expect(land.connect(publicMinter6).mintLands(
        1,
        { value: mintPrice }
      ))).to.be.revertedWith("Max public lands exceeded");

      expect(await land.totalLandsMinted()).to.equal(totalLandsMinted + 1);
      totalLandsMinted += 1;

      expect(await land.MAX_PUBLIC_LANDS()).to.eq(totalLandsMinted);

      ///////////////// BURN ROUND ///////////////////////
      // const oldSupply = await land.MAX_LANDS();
      // await land.burnSupply(await land.totalSupply());
      // const newSupply = await land.MAX_LANDS();
      // expect(await land.totalSupply()).to.eq(newSupply);
      // expect(oldSupply).to.gt(newSupply);
      ///////////////////////////////////////////////////

      // hidden uri
      const hiddenURI = "https://api.wb.com/token/hidden";
      await land.setHiddenMetadataURI(hiddenURI);
      totalSupply = (await land.totalSupply()).toNumber();
      for (let i = 1; i <= totalSupply; i++) {
        expect(await land.tokenURI(i)).to.eq(hiddenURI);
      }

      // reveal
      const revealURI = "https://api.wb.com/token/";
      await land.setBaseURI(revealURI);
      await land.reveal();

      for (let i = 1; i <= totalSupply; i++) {
        expect(await land.tokenURI(i)).to.eq(`${revealURI}${i}`);
      }

      const balanceBefore = await provider.getBalance(owner.address);

      const landBalance = await provider.getBalance(land.address);
      const tx = await land.withdraw(landBalance);
      await tx.wait();
      expect(await provider.getBalance(land.address)).to.eq(0);

      const receipt = await provider.getTransactionReceipt(tx.hash);
      const fee = receipt.gasUsed.mul(receipt.effectiveGasPrice);

      const balanceAfter = await provider.getBalance(owner.address);
      expect(balanceAfter.sub(balanceBefore)).to.eq(landBalance.sub(fee));
    });
  });
});
