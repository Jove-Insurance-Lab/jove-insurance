//SPDX-License-Identifier: SimPL-2.0
pragma solidity >=0.6.0 <0.7.0;
import "./@openzeppelin/token/ERC20/ERC20.sol" ;
import "./@openzeppelin/token/ERC721/ERC721.sol";

import "./IStakingPool.sol";
import "./IUpgradable.sol";
//import "./ERC20TokenRegister.sol"; 
import "./PriceMetaInfoDB.sol"; 

abstract contract JoveProductTokenBase is ERC20, IUpgradable
{
    string public category;
    string public subCategory;
    bytes8 coinName;
    
    uint256 public expireTimestamp; 
    uint256 public closureTimestamp;
    
    address public tokenAddress;
    
	function expiresTimestamp() view public returns(uint256){ 
		return expireTimestamp; //结算时期
	}
	
	bool public isValid; 

	bool public needPay; 

	uint256 public totalSellQuantity; 
	
	uint256 public totalPremiums; 	

	mapping(address=>uint256) private usrPremium;

	IStakingPool public stakingPool;
	address public stakingPoolToken;
    //ERC20TokenRegister internal _tokenRegister;

	PriceMetaInfoDB  _priceMetaInfoDb;

	event EventStatusChanged(uint256 totalSellQuantity,uint256 totalPremiums);
	event EventBuy(address indexed user,uint256 premium,uint256 quantity);
	
	constructor(string memory categoryValue,string memory subCategoryValue,
		string memory tokenNameValue,string memory tokenSymbolValue,
		uint256 closureTimestampValue)
		ERC20(tokenNameValue, tokenSymbolValue) IUpgradable() internal 
    {
		_setupDecimals(0);
		category = categoryValue;
		subCategory = subCategoryValue;

		closureTimestamp = closureTimestampValue;
		expireTimestamp = closureTimestampValue;
		totalSellQuantity = 0;
		totalPremiums = 0;
		
		isValid = true;
		needPay = false;
    }	

    function updateDependentContractAddress() public virtual override {
		address tokenRegisterAddr=register.getContract("TKRG");
        assert(tokenRegisterAddr!=address(0));
        //_tokenRegister=ERC20TokenRegister(tokenRegisterAddr);
		_priceMetaInfoDb=PriceMetaInfoDB(register.getContract("MIDB"));
    } 

	function setStakingPool(address poolAddress, address stakingPoolTokenAddress) public onlyOwner returns(bool){
		require(address(stakingPool) == address(0),"The setStakingPool() can only be called once");
		stakingPool = IStakingPool(poolAddress);
		stakingPoolToken = stakingPoolTokenAddress;
		tokenAddress = stakingPool.getTokenAddress();
		return true;
	}

    modifier onlyPool(){
        require(address(_msgSender())==address(stakingPool) || _msgSender() == stakingPoolToken);
        _;
    }

	function getAddress() view public returns(address) {
	    return address(stakingPool);
	}
	
	function burn(address account, uint256 amount) public onlyPool {
		_burn(account,amount);
	}

	function statusChanged() internal {
		emit EventStatusChanged(totalSellQuantity,totalPremiums);
	}

	function remaining() public view returns(uint256) { 
		return stakingPool.productTokenRemainingAmount(address(this));
	}

	function verifyPrice(address priceNodePublicKey, uint256 price, uint256 expiresAt, uint8 v, bytes32 r, bytes32 s) public view returns(bool){
		require(address(_priceMetaInfoDb)!=address(0),"priceMetaInfoDb not set");
		require(_priceMetaInfoDb.PRICE_NODE_PUBLIC_KEY()==priceNodePublicKey,"The price node public key is not valid");

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                priceNodePublicKey,
                price,
                expiresAt
            )
        );
		return _priceMetaInfoDb.verifySign(messageHash,priceNodePublicKey,expiresAt,v,r,s);
    }
        
    function _checkBuyAvailable(address priceNodePublicKey, uint256 quantity, uint256 price, uint256 expiresAt, uint8 v, bytes32 r, bytes32 s) view internal returns(bool){
        require(now < closureTimestamp,"The proudct has expired");
		require(quantity>0, "compensationAmount should > 0");
		require(isValid, "the product has been closed");
		require(quantity <= remaining(), "quantity should <= remaining");
		require(price > 0, "premium should > 0");
		require(verifyPrice(priceNodePublicKey,price,expiresAt,v,r,s),"buy verify sign failed");
        return true;
    }

	function _buy(address account, uint256 amount, uint256 quantity, address priceNodePublicKey, uint256 price, uint256 expiresAt, uint8 v, bytes32 r, bytes32 s) internal returns(bool) {
        //if (!_checkBuyAvailable(priceNodePublicKey,quantity,price,expiresAt,v,r,s)){
            //return false;
        //}
		_mint(account, quantity);
		
		totalPremiums = totalPremiums.add(amount);
		totalSellQuantity = totalSellQuantity.add(quantity);

		emit EventBuy(_msgSender(),amount,quantity);
		statusChanged();
		return true;
	}

    function _checkWithdrawAvailable(address account, address priceNodePublicKey, uint256 withdrawQuantity, uint256 price, uint256 expiresAt, uint8 v, bytes32 r, bytes32 s) view internal returns(bool){
		require(isValid,"the product has been closed");
		uint256 quantity = balanceOf(account);
		require(withdrawQuantity<=quantity,"invalid withdraw quantity");
		//require(verifyPrice(priceNodePublicKey,price,expiresAt,v,r,s),"withdraw vertify sign failed");
        return true;
    }

    function _calcWithDrawAmount(uint256 quantity, uint256 price,uint256 totalSellQty) view public returns(uint256){
		uint256 avgPrice = totalPremiums.div(totalSellQty);
		uint256 returnPrice = avgPrice < price ? avgPrice : price;
		uint256 amount = returnPrice.mul(quantity);
		//uint256 returnAmount =  amount.mul(1000 - _priceMetaInfoDb.PRODUCT_WITHDRAW_PERCENT()).div(1000);
		uint256 returnAmount =  amount.mul(1000 - 300).div(1000);
        return returnAmount;
    }

	function _withdraw(address account, address nodePublicKey, uint256 quantity, uint256 price, uint256 expiresAt, uint8 _v, bytes32 _r, bytes32 _s) internal returns(uint256){
        //if (!_checkWithdrawAvailable(nodePublicKey,quantity,price,expiresAt,_v,_r,_s)){
            //return 0;
        //}
		_burn(account, quantity);
		uint256 returnAmount =  _calcWithDrawAmount(quantity,price,totalSellQuantity);
		totalSellQuantity = totalSellQuantity.sub(quantity);
		totalPremiums = totalPremiums.sub(returnAmount);

   		statusChanged();
        return returnAmount;
	}    	
}
