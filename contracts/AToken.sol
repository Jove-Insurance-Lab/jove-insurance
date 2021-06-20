//SPDX-License-Identifier: SimPL-2.0
pragma solidity >=0.6.0 <0.7.0;
import "./@openzeppelin/token/ERC20/ERC20.sol";
import "./@openzeppelin/token/ERC20/SafeERC20.sol";
import "./@openzeppelin/token/ERC20/IERC20.sol";
import "./ProxyOwnable1.sol";

contract AToken is ERC20, ProxyOwnable {
    using SafeERC20 for IERC20;
    
    constructor() ERC20("AToken", "AT") public {
    	setOwnable(_msgSender());
    } 
    
    function mint(address account, uint256 amount) public onlyOwner {
    	_mint(account, amount);
    }
}
