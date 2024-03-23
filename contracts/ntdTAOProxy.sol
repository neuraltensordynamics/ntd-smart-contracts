// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

contract NtdTAOProxy is TransparentUpgradeableProxy {
  constructor(
    address _logic,
    address admin,
    bytes memory _data
  ) TransparentUpgradeableProxy(_logic, admin, _data) {}
}
