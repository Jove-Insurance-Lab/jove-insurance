//SPDX-License-Identifier: SimPL-2.0
pragma solidity >=0.6.0 <0.7.0;


interface IJoveProductToken{
    function totalSellQuantity() external view returns(uint256);
    function expiresTimestamp() external view returns(uint256);
    function totalPremiums() external view returns(uint256);
    function needPay() external view returns(bool);
    function isValid() external view returns(bool);
    function balanceOf(address account) external view returns (uint256);
    function burn(address account, uint256 amount) external;
    function calcDistributePremiums() external view returns(uint256,uint256);
    function approvePaid() external;
    function rejectPaid() external;
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function isClaim() external returns(bool);
    function getExpireTimestamp() external returns(uint256);
    function closureTimestamp() external returns(uint256);
}


interface IStakingPool 
{
    function calcPremiumsRewards(uint256 accumulateTimeStampsRewards) external view returns(uint256);

    function totalNeedPayFromStaking() external view returns(uint256); 

    function totalRealPayFromStaking() external view returns(uint256) ; 

    function payAmount(address productTokenAddr) external view returns(uint256); 

    function productTokenRemainingAmount(address productTokenAddr) external view returns(uint256);
    function productTokenExpireTimestamp(address productAddr) external view returns(uint256);
    function calculateCapacity() external view returns(uint256);
    function updateTokenHolder(address account, uint256[] memory holderInfo, uint256 timestamp) external;
    function removeTokenHolder(address account, uint256[] memory holderInfo, uint256 stakingtimeamount) external;
    function productToken(address productAddr) external view returns(IJoveProductToken);
    function updataPremiumsRewards(uint256 reward) external;
    function deletePremiumsRewards(uint256 reward) external;
    function setNeedPayFlag(bool needPay, address productTokenAddr, uint256 timestamp) external;
    function setNeedPayFlagAll(bool[] memory needPay, address[] memory productTokenAddr, uint256[] memory timestamp) external;
    function queryAndCheckClaimAmount(address userAccount, address productTokenAddr) view external returns(uint256,uint256/*token balance*/);
    function getTokenAddress() view external returns(address);
    function productNeedClaim(uint256 quantity, uint256 expireTimestamp, address productAddr) external;
}

interface IStakingPoolToken{
    function getTokenHolderAmount(uint256 tokenId,address poolAddr) view external returns(uint256);
    function getTokenHolder(uint256 tokenId) view external returns(uint256,uint256,uint256);
    function coinHolderRemainingPrincipal(uint256 tokenId) view external returns(uint256);
    function bookkeepingFromPool(uint256 amount, address productTokenAddr) external;
    function isTokenExist(uint256 tokenId) view external returns(bool);
}
