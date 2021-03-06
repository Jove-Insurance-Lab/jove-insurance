
//           DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
//                   Version 2, December 2004
// 
//Copyright (C) 2021 Joveproject <Joveproject@yahoo.com>
//
//Everyone is permitted to copy and distribute verbatim or modified
//copies of this license document, and changing it is allowed as long
//as the name is changed.
// 
//           DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
//  TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
//
// You just DO WHAT THE FUCK YOU WANT TO.
//SPDX-License-Identifier: SimPL-2.0
pragma solidity >=0.6.0 <0.7.0;

import "./joveRegister.sol";
import "./jovePausable.sol";

abstract contract IUpgradable is JovePausable{

    JoveRegister public register;
    address public registerAddress;


    function  updateDependentContractAddress() public virtual;  

    function updateRegisterAddress(address registerAddr) external {
        if (address(register) != address(0)) {
            require(register.isOwner(_msgSender()), "Just the register's owner can call the updateRegisterAddress()"); 
        }
        register = JoveRegister(registerAddr);
        setOwnable(registerAddr);
        registerAddress=registerAddr;
        //updateDependentContractAddress();
    }

}
