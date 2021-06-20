//SPDX-License-Identifier: SimPL-2.0

pragma solidity >=0.6.0 <0.7.0;

pragma experimental ABIEncoderV2;

import "./@openzeppelin/math/SafeMath.sol";
import "./IJoveVault.sol";
import "./jovePausable.sol";
import "./@openzeppelin/utils/EnumerableSet.sol";
import "./@openzeppelin/math/SafeMath.sol";


interface IJoveProductToken{
    
    function buy(address account, address priceNodePublicKey, uint256 quantity, uint256 price, 
        uint256 expiresAt, uint8 _v, bytes32 _r, bytes32 _s) external view returns(bool);
        
    function sell(address account, address priceNodePublicKey, uint256 quantity, uint256 price, 
            uint256 expiresAt, uint8 _v, bytes32 _r, bytes32 _s) external view returns(bool);
    
    function closureTimestamp() external view returns(uint256);
    
    function expiresTimestamp() external view returns(uint256);
}

interface IStakingPoolToken{
    function deposite(address account, uint256 principal, uint256 supply, uint256 balance, address pool_address) external;
    function withdraw(address account, uint256 amount, uint256 supply, uint256 balance, address pool_address) external;
    function claim(address pool_address, address productTokenAddr, address account) external;
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

library IterableMapping {

    // Iterable mapping from address to uint;

    struct Map {

        uint[] keys;

        mapping(uint => address) values;

        mapping(uint => uint) indexOf;

        mapping(uint => bool) inserted;

    }



    function get(Map storage map, uint key) public view returns (address) {

        return map.values[key];

    }



    function getKeyAtIndex(Map storage map, uint index) public view returns (uint) {

        return map.keys[index];

    }



    function size(Map storage map) public view returns (uint) {

        return map.keys.length;

    }



    function set(Map storage map, uint key, address val) public {

        if (map.inserted[key]) {

            map.values[key] = val;

        } else {

            map.inserted[key] = true;

            map.values[key] = val;

            map.indexOf[key] = map.keys.length;

            map.keys.push(key);

        }

    }



    function remove(Map storage map, uint key) public {

        if (!map.inserted[key]) {

            return;

        }



        delete map.inserted[key];

        delete map.values[key];



        uint index = map.indexOf[key];

        uint lastIndex = map.keys.length - 1;

        uint lastKey = map.keys[lastIndex];



        map.indexOf[lastKey] = index;

        delete map.indexOf[key];



        map.keys[index] = lastKey;

        map.keys.pop();

    }

}

contract JoveController is JovePausable 
{
	using SafeMath for uint256;
	using IterableMapping for IterableMapping.Map;
	using EnumerableSet for EnumerableSet.UintSet;
	
	
	IterableMapping.Map private _indexProductMap;
	IterableMapping.Map private _indexUnderwritingMap;
	//mapping(address => address) private UnderwritingToAddress;
	mapping(address => address) private poolToPoolMap;
	mapping(uint256 => uint256) private closureTimestamp;
	mapping(uint256 => uint256) private expireTimestamp;
	mapping(uint256 => uint256) private totalSellQuantity;
	EnumerableSet.UintSet private inClaimingProduct;
	uint256 _nextProductIndex;
	uint256 _nextUnderwritingIndex;
	
	IJoveVault public joveVault;
	
	uint256[] private claimAbleMap;
	
	event NewProductAdded(address productTokenAddress);
	event NewUnderwritingTokenAdded(address stakingPoolTokenAddress);

	constructor(address ownable) JovePausable() public {
		setOwnable(ownable);
	}
	
	function updateVaultAddress(address _joveVaultAddress) public onlyOwner  returns(bool) {
	    require(_joveVaultAddress != address(0), "0x is not a useful address");
	    joveVault = IJoveVault(_joveVaultAddress);
            return true;
	}

	function addProduct(address productTokenAddress) public onlyOwner returns(bool){
		_indexProductMap.set(_nextProductIndex, productTokenAddress);
		uint256 closuretimestamp = IJoveProductToken(productTokenAddress).closureTimestamp();
		closureTimestamp[_nextProductIndex] = closuretimestamp;
		_nextProductIndex = _nextProductIndex.add(1);
		emit NewProductAdded(productTokenAddress);
		return true;
	}

	function getProduct(uint256 index) public view returns(address) {
		require(index < productSize(),"index should < productSize");
		address tokenAddress = _indexProductMap.get(index);
		return tokenAddress;
	}
	
	function productSize() public view returns(uint256) {
		return _nextProductIndex;
	}

	function addUnderWrtiting(address stakingPoolTokenAddress, address stakingPoolAddress) public onlyOwner returns(bool){
		_indexUnderwritingMap.set(_nextUnderwritingIndex, stakingPoolTokenAddress);
		//UnderwritingToAddress[stakingPoolTokenAddress] = stakingPoolAddress;
		_nextUnderwritingIndex = _nextUnderwritingIndex.add(1);
		poolToPoolMap[stakingPoolTokenAddress] = stakingPoolAddress;
		emit NewUnderwritingTokenAdded(stakingPoolTokenAddress);
		return true;
	}

	function getUnderWrtiting(uint256 index) public view returns(address) {
		require(index < UnderWrtitingSize(),"index should < productSize");
		address tokenAddress = _indexUnderwritingMap.get(index);
		return tokenAddress;
	}
	
	function UnderWrtitingSize() public view returns(uint256) {
		return _nextUnderwritingIndex;
	}

	function buyProductToken(uint256 index, uint256 amount, address account, address priceNodePublicKey, uint256 oraclePrice, uint8 _v, bytes32 _r, bytes32 _s) public onlyOwner returns(bool) {
	    require(closureTimestamp[index] > now, "the productToken has closed");
	    address tokenAddress = _indexProductMap.get(index);
	    IJoveProductToken productToken = IJoveProductToken(tokenAddress);
	    uint256 expiresAt = productToken.expiresTimestamp();
	    require(productToken.buy(account, priceNodePublicKey, amount, oraclePrice, expiresAt, _v, _r, _s), "Buying profuct is error");
	    totalSellQuantity[index] = amount.add(totalSellQuantity[index]);
	    return true;
	}
	
	function sellProductToken(uint256 index, uint256 amount, address account, address priceNodePublicKey, uint256 oraclePrice, uint8 _v, bytes32 _r, bytes32 _s) public onlyOwner returns(bool) {
	    require(closureTimestamp[index] > now, "the productToken has closed");
	    address tokenAddress = _indexProductMap.get(index);
	    IJoveProductToken productToken = IJoveProductToken(tokenAddress);
	    uint256 expiresAt = productToken.expiresTimestamp();
	    require(productToken.sell(account, priceNodePublicKey, amount, oraclePrice, expiresAt, _v, _r, _s), "Selling profuct is error");
	    totalSellQuantity[index] = totalSellQuantity[index].sub(amount);
	    return true;
	}

	function depositUnderwriting(uint256 index, uint256 principal, address account) public onlyOwner{
	    address stakingPoolTokenAddress = _indexUnderwritingMap.get(index);
	    address stakingPoolAddress = poolToPoolMap[stakingPoolTokenAddress];
        IStakingPoolToken underWritingToken = IStakingPoolToken(stakingPoolTokenAddress);
        uint256 balance = joveVault.balance();
        uint256 supply = joveVault.totalsupply();
        
	    underWritingToken.deposite(account, principal, supply, balance, stakingPoolAddress);
	}
	
	function withdrawUnderwriting(uint256 index, uint256 amount, address account) public onlyOwner{
	    address stakingPoolTokenAddress = _indexUnderwritingMap.get(index);
	    address stakingPoolAddress = poolToPoolMap[stakingPoolTokenAddress];
        IStakingPoolToken underWritingToken = IStakingPoolToken(stakingPoolTokenAddress);
        uint256 balance = joveVault.balance();
        uint256 supply = joveVault.totalsupply();
        
	    underWritingToken.withdraw(account, amount, supply, balance, stakingPoolAddress);
	}

    function setProductClaim(uint256 index, string memory subjectType) public onlyOwner {
        uint256 timestamp = now;
        //uint256 expireTimestamp = _priceMetaInfoDb.getPeriod(subjectType); //todo
        uint256 expiretimestamp = 1209600; //todo
        expiretimestamp  = expiretimestamp.add(timestamp);
        expireTimestamp[index] = expiretimestamp;
        closureTimestamp[index] = now;
        for(uint i = 0; i < _indexUnderwritingMap.size(); ++i) {
            address stakingPoolAddress = poolToPoolMap[_indexUnderwritingMap.get(i)];
            IStakingPool underWriting= IStakingPool(stakingPoolAddress);        
            underWriting.productNeedClaim(totalSellQuantity[index],expiretimestamp, _indexProductMap.get(index));            
        }
        inClaimingProduct.add(index);
    }
    
	function getClaim() public onlyOwner returns(uint256[] memory){
	    uint256[] memory claimPool = new uint256[](claimAbleMap.length);
	    for(uint i = 0; i < claimAbleMap.length; ++i) {
	        claimPool[i] = claimAbleMap[i];
	    }
	    
	    return claimPool;
	}	

	function claim(uint256 productIndex, uint256 stakingIndex, address account) public onlyOwner{
	    address tokenAddress = _indexProductMap.get(productIndex);
	    address stakingPoolTokenAddress = _indexUnderwritingMap.get(stakingIndex);
	    address stakingPoolAddress = poolToPoolMap[stakingPoolTokenAddress];
	    IStakingPoolToken underWritingToken = IStakingPoolToken(stakingPoolTokenAddress);
	    underWritingToken.claim(stakingPoolAddress, tokenAddress, account);
	}
	
	function setStakingPoolNeedPayFlagAll() public onlyOwner{
	    if(inClaimingProduct.length() == 0) {
	        for(uint i = 0; i < _indexUnderwritingMap.size(); ++i) {
	            IStakingPool pool = IStakingPool(poolToPoolMap[_indexUnderwritingMap.get(i)]);
	            bool[] memory needPay = new bool[](_indexProductMap.size());
	            uint256[] memory timestamps = new uint256[](_indexProductMap.size());
	            address[] memory _productTokenAddress = new address[](_indexProductMap.size());
	            for(uint j = 0; j < timestamps.length; ++j) {
	                timestamps[j] = now;
	                _productTokenAddress[j] = _indexProductMap.get(j);
	            }
	            pool.setNeedPayFlagAll(needPay, _productTokenAddress, timestamps);
	        }
	    } else {
	        address[] memory remainProductToken;
	        uint num = 0;
	        for(uint index = 0; index < _indexProductMap.size(); ++index){
	            if(inClaimingProduct.contains(index) == false){
	                remainProductToken[num] = _indexProductMap.get(index);
	                num = num.add(1);
	            }
	        }
	        for(uint i = 0; i < _indexUnderwritingMap.size(); ++i) {
	            IStakingPool pool = IStakingPool(poolToPoolMap[_indexUnderwritingMap.get(i)]);
	            bool[] memory needPay = new bool[](_indexProductMap.size());
	            uint256[] memory timestamps = new uint256[](remainProductToken.length);
	            address[] memory _productTokenAddress = new address[](remainProductToken.length);
	            for(uint j = 0; j < timestamps.length; ++j) {
	                timestamps[j] = now;
	                _productTokenAddress[j] = remainProductToken[j];
	            }
	            pool.setNeedPayFlagAll(needPay, _productTokenAddress, timestamps);
	        }
	        
	    }
	}

	function setStakingPoolNeedPayFlag(uint256 index, bool needPay) public onlyOwner{
	    address producttokenaddress = _indexProductMap.get(index);
	    uint256 timestamp = now;
            for(uint i = 0; i < _indexUnderwritingMap.size(); ++i) {
                IStakingPool pool = IStakingPool(poolToPoolMap[_indexUnderwritingMap.get(i)]);	    
                pool.setNeedPayFlag(needPay, producttokenaddress, timestamp);
	    }	
	}	
}
