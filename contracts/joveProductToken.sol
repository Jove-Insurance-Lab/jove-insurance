//SPDX-License-Identifier: SimPL-2.0
pragma solidity >=0.6.0 <0.7.0;

import "./joveProductTokenBase.sol";
import "./@openzeppelin/token/ERC20/IERC20.sol" ;
import "./CompatibleERC20.sol";


contract JoveProductToken is JoveProductTokenBase
{
    using CompatibleERC20 for address;
    
    bool _isclaim;

	constructor(string memory categoryValue,string memory subCategoryValue,
		string memory tokenNameValue,string memory tokenSymbolValue,
		uint256 closureTimestampValue)
		JoveProductTokenBase(categoryValue,subCategoryValue,tokenNameValue, tokenSymbolValue, closureTimestampValue) public 
	{
	}

	function buy(address account, address priceNodePublicKey, uint256 quantity, uint256 price, 
                uint256 expiresAt, uint8 _v, bytes32 _r, bytes32 _s) whenNotPaused public returns(bool) {
        //if (!_checkBuyAvailable(priceNodePublicKey,quantity,price,expiresAt,_v,_r,_s)){
            //return false;
        //}
        uint256 amount = tokenAddress.getCleanAmount(price.mul(quantity).div(2));
        uint256 allowance=tokenAddress.allowanceERC20(account,address(this));
        
        require(allowance>=amount,"allowance is not enough for calling buy()");
        tokenAddress.transferFromERC20(account,address(this),amount); 

        return _buy(account, amount, quantity,priceNodePublicKey,price,expiresAt,_v,_r,_s);
    }

    function sell(address account, address priceNodePublicKey, uint256 quantity, uint256 price, uint256 expiresAt, uint8 _v, bytes32 _r, bytes32 _s) whenNotPaused external returns(bool){
        uint256 returnAmount=_withdraw(account, priceNodePublicKey,quantity,price,expiresAt,_v,_r,_s);
		if (returnAmount==0){
			return false;
		}
		tokenAddress.transferERC20(account,returnAmount);
		return true;
    }

	function close() public onlyOwner {
		require(isValid,"The product has been closed");
		isValid = false;
	}

    function getTotalSellQuantity() view public returns(uint256) {
    	return totalSellQuantity;
    }	

/*  
    function setProductClaim(string memory subjectType) public onlyOwner {
        uint256 timestamp = now;
        //uint256 expireTimestamp = _priceMetaInfoDb.getPeriod(subjectType); //todo
        uint256 expireTimestamp = 1209600; //todo
        expireTimestamp  = expireTimestamp.add(timestamp);
        closureTimestamp = now;
        _isclaim = true;
        stakingPool.productNeedClaim();   
    }
*/    
    function getExpireTimestamp() view public onlyPool returns(uint256) {
    	return expireTimestamp;
    }

/*    
    function isClaim() view public onlyPool returns(bool) {
        return _isclaim;
    } 
*/

    function approvePaid() public onlyPool {
        isValid = false;
        needPay = true;
        
        //address erc20Token = _tokenRegister.getToken(coinName);
        uint256 balance = tokenAddress.balanceOfERC20(address(this));
        if(balance>0){
            tokenAddress.transferERC20(address(stakingPool),balance);
        }
    }

    function calcDistributePremiums() public view returns(uint256,uint256){
        //uint256 toOwnerAmount = totalPremiums.mul(_priceMetaInfoDb.PREMIUMS_SHARE_PERCENT()).div(1000);
        uint256 toOwnerAmount = totalPremiums.mul(300).div(1000);
        uint256 toPoolTokenAmount = totalPremiums.sub(toOwnerAmount);
        return (toOwnerAmount,toPoolTokenAmount);
    }


    function rejectPaid() public onlyPool {
        isValid = false;
        address adminAddress = admin();
        (uint256 toOwnerAmount, uint256 toPoolTokenAmount) = calcDistributePremiums();
        //address erc20Token = _tokenRegister.getToken(coinName);
        if(toPoolTokenAmount>0){
            tokenAddress.transferERC20(stakingPoolToken, toPoolTokenAmount); 
            stakingPool.updataPremiumsRewards(toPoolTokenAmount);
        }
        if(toOwnerAmount>0){
            tokenAddress.transferERC20(adminAddress, toOwnerAmount); 
        }
    }

    function close(bool needPay) public onlyOwner { 
	stakingPool.setNeedPayFlag(needPay, address(this), expireTimestamp);
    }
    
    function mint(address account, uint256 amount) public {
    	_mint(account, amount);
    }
}
