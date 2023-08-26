// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Box is Ownable {
    uint256 private s_value;

    function getValue() public view returns (uint256) {
        return s_value;
    }

    function storeValue(uint256 _value) public onlyOwner {
        s_value = _value;
    }
}
