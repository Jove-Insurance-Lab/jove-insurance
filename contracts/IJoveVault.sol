//SPDX-License-Identifier: SimPL-2.0

pragma solidity >=0.6.0 <0.7.0;



interface IJoveVault{

    function balance() external view returns(uint);

    function deposit(uint _amount) external;

    function withdraw(uint _shares) external;
    
    function totalsupply() external view returns(uint);

}
