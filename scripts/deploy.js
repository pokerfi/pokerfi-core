const { ethers } = require("hardhat");

async function main() {
    const USDT = "0x55d398326f99059fF775485246999027B3197955";

    const PokerToken = await ethers.getContractFactory("PokerToken");
    const pokerToken = await PokerToken.deploy();
    console.log("PokerToken deployed to:", pokerToken.address);

    const Poker = await ethers.getContractFactory("Poker");
    const poker = await Poker.deploy();
    console.log("Poker deployed to:", poker.address);

    const CardSolt = await ethers.getContractFactory("CardSolt");
    const cardSolt = await CardSolt.deploy(pokerToken.address, poker.address);
    console.log("CardSolt deployed to:", cardSolt.address);

    const CardStore = await ethers.getContractFactory("CardStore");
    const cardStore = await CardStore.deploy(poker.address);
    console.log("CardStore deployed to:", cardStore.address);

    const CardMine = await ethers.getContractFactory("CardMine");
    const cardMine = await CardMine.deploy(USDT, pokerToken.address, poker.address);
    console.log("CardMine deployed to:", cardMine.address);

    const CardMarket = await ethers.getContractFactory("CardMarket");
    const cardMarket = await CardMarket.deploy(poker.address);
    console.log("CardMarket deployed to:", cardMarket.address);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
