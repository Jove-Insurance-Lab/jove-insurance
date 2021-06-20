
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

import "./@openzeppelin/GSN/Context.sol";
import "./@openzeppelin/access/Ownable.sol";
import "./@openzeppelin/utils/Address.sol";

abstract contract ProxyOwnable is Context, Ownable{
    using Address for address;

    address private _owner;
    address private _admin;

    constructor() public{
    }


    function setOwnable(address ownable) internal{ 
    	require(ownable!=address(0), "setOwnable should not be 0");
    	require(_owner==address(0), "_owner should be 0");
        _owner = ownable;
        setAdminable(ownable);
    }

    function setAdminable(address adminable) internal{
    	require(adminable!=address(0), "setOwnable should not be 0");
	require(_admin==address(0), "_owner should be 0");
	_admin = adminable;
    }

    modifier onlyAdmin() {
        require(_admin == _msgSender(), "you are not the adminster");
        _;
    }

    function admin() view public returns(address){
        return _admin;
    }
}
