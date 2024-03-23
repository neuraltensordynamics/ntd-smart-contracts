const { ethers, upgrades } = require("hardhat");

async function main() {

    const Staking = await ethers.getContractFactory("NtdTAO");

    const owner = await ethers.getSigners();
    const supply = BigInt(hre.ethers.parseUnits("100000", "gwei"));
    const staking = await upgrades.deployProxy(Staking, [owner[0].address, supply], { initializer: 'initialize' });

    await staking.waitForDeployment();
    console.log("Staking deployed to:", await staking.getAddress());

    //TODO: staking.call(setWtao, [wTaoContractAddress]);
    //TODO: call grantRole(MANAGE_STAKING_CONFIG_ROLE, owner[0].address);
    //TODO: call maxDepositPerRequest(100);
    //TODO: call setNativeTokenReceiver(FinneyAddress);
    //TODO: call setProtocolVault(ethAddress);
    //TODO: call grantRole(MANAGE_STAKING_CONFIG_ROLE, owner[0].address);
    //TODO: call setMinStackingAmount(100000000);
    //TODO: call setMaxStackingAmount(1e18)
    //TODO: call setUpperExchangeRate(1e18);
    //TODO: call setLowerExchangeRate(1e18);
    //TODO: call setExchangeRate(1e18);

}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
