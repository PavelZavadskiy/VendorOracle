require('dotenv').config();

let VendorOracle = artifacts.require("./VendorOracle.sol");

module.exports = async function (deployer) {
    await deployer.deploy(VendorOracle, process.env.SST_TOKEN);
}