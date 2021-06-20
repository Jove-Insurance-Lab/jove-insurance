//SPDX-License-Identifier: SimPL-2.0

pragma solidity >=0.6.0 <0.7.0;

pragma experimental ABIEncoderV2;



import "./IStakingPool.sol";

import "./IJoveVault.sol";

import "./PriceMetaInfoDB.sol";

import "./IUpgradable.sol";

import "./@openzeppelin/math/SafeMath.sol";

import "./@openzeppelin/math/Math.sol";

import "./@openzeppelin/utils/ReentrancyGuard.sol";

//import "./ERC20TokenRegister.sol";

import "./CompatibleERC20.sol";

import "./@openzeppelin/utils/EnumerableSet.sol";



library IterableMapping {

    // Iterable mapping from address to uint;

    struct Map {

        address[] keys;

        mapping(address => uint) values;

        mapping(address => uint) indexOf;

        mapping(address => bool) inserted;

    }



    function get(Map storage map, address key) public view returns (uint) {

        return map.values[key];

    }



    function getKeyAtIndex(Map storage map, uint index) public view returns (address) {

        return map.keys[index];

    }



    function size(Map storage map) public view returns (uint) {

        return map.keys.length;

    }



    function set(Map storage map, address key, uint val) public {

        if (map.inserted[key]) {

            map.values[key] = val;

        } else {

            map.inserted[key] = true;

            map.values[key] = val;

            map.indexOf[key] = map.keys.length;

            map.keys.push(key);

        }

    }



    function remove(Map storage map, address key) public {

        if (!map.inserted[key]) {

            return;

        }



        delete map.inserted[key];

        delete map.values[key];



        uint index = map.indexOf[key];

        uint lastIndex = map.keys.length - 1;

        address lastKey = map.keys[lastIndex];



        map.indexOf[lastKey] = index;

        delete map.indexOf[key];



        map.keys[index] = lastKey;

        map.keys.pop();

    }

}



contract StakingPool is IStakingPool, IUpgradable, ReentrancyGuard

{

    using SafeMath for uint256;

    using CompatibleERC20 for address;

    using IterableMapping for IterableMapping.Map;

    using EnumerableSet for EnumerableSet.AddressSet;



    address [] private tokenHolderIds;  

    bytes8 coinName;

    address public tokenAddress;

    IJoveVault public joveVault;





    mapping(address/*account*/=>uint256) _timestamps; 

    mapping(address/*account*/=>uint256) _tokenStakingTimeAmount;

    

    

    IStakingPoolToken public stakingPoolToken;

    //ERC20TokenRegister _tokenRegister;

    PriceMetaInfoDB  _priceMetaInfoDb;
    
    address public controllerAddr;

    uint256 public minStakingAmount; 



	uint256 public capacityLimitPercent; 



    //uint256 private _totalStakingAmount; 



    uint256 public _totalStakingTimeAmount; 



    uint256 private _totalNeedPayFromStaking; 



    uint256 private _totalRealPayFromStaking; 

    

    uint256 public expireTimestamp;



    mapping(address=>uint256) private _payAmount;

    mapping(address=>bool) public _isClosed;

    mapping(address=>bool) public claimEnable;

    

    uint256 totalPoolTokenPremiums;



    uint256 _totalPremiumsAfterClose;

    

    bool public needPayFlag;

    

    IterableMapping.Map private _claimQuantity;

    IterableMapping.Map private _claimexpireTimestamp;

    EnumerableSet.AddressSet private productTokenAddrs;

    

    

    //address[] public productTokenAddrs;

    uint256 _totalClaimQuantity;



    constructor(uint256 minStakingAmount_, uint256 capacityLimitPercent_, bytes8 _coinName, address _tokenAddress, address _joveVaultAddress, address _controllerAddr) ReentrancyGuard() public{

        minStakingAmount = minStakingAmount_;

        capacityLimitPercent = capacityLimitPercent_;

        _totalClaimQuantity = 0;

        totalPoolTokenPremiums=0;

        coinName = _coinName;

        tokenAddress = _tokenAddress;

        joveVault = IJoveVault(_joveVaultAddress);
        
        controllerAddr = _controllerAddr;

    }



    function sqrt(uint256 x) internal pure returns (uint256) {

    	uint256 z = (x + 1) / 2;

    	uint256 y = x;

    	while(z < y) {

    	    y = z;

    	    z = (x / z + z) / 2;

    	}

    	

    	return y;

    }



    function getTimesStamps(address account) view public returns(uint256) {

    	return _timestamps[account]; 

    } 

    

    function calculateCapacity() view public override returns(uint256) {

        uint256 activeCovers = 0;

        for(uint256 i=0;i<productTokenAddrs.length();++i) {

            IJoveProductToken productToken = IJoveProductToken(productTokenAddrs.at(i));

            activeCovers = activeCovers.add(productToken.totalSellQuantity());

        }

        uint256 _totalStakingAmount = joveVault.balance();

        uint256 maxMCRCapacity = _totalStakingAmount.mul(capacityLimitPercent).div(100);

        maxMCRCapacity = maxMCRCapacity.sub(_totalClaimQuantity);

        uint256 availableCapacity = activeCovers >= maxMCRCapacity ? 0 : maxMCRCapacity.sub(activeCovers);

        return availableCapacity;

    }



    function productTokenRemainingAmount(address productTokenAddr) view public override returns(uint256){ 

        require(productTokenAddr!=address(0),"The productToken should not be 0");

        return calculateCapacity();

    }



    function tokenHolderIdLength() view public returns(uint256){

        return tokenHolderIds.length;

    }    



    

    function setProductToken(address[] memory productAddress) onlyOwner public returns(bool){

        for(uint256 i=0;i<productAddress.length;++i) {

            address tokenAddr = productAddress[i];

            require(tokenAddr != address(0),"The token address is 0");

            productTokenAddrs.add(tokenAddr);

        }

		return true;

	}

    

    modifier onlyPoolToken(){

        require(address(stakingPoolToken)==address(_msgSender()));

        _;

    }

    modifier onlyController(){

        require(controllerAddr == _msgSender());

        _;
            	
    }

    modifier onlyProductToken(){

        require(productTokenAddrs.contains(_msgSender()));

        _;

    }    

    modifier onlyOwnerAndController(){
    
        require(productTokenAddrs.contains(_msgSender()) || controllerAddr == _msgSender());

        _;
    }

    function setExpireTimestamp(uint256 closeTimeStamp) onlyOwner public {

        expireTimestamp = closeTimeStamp;

    }



    function updateTokenHolder(address account, uint256[] memory holderInfo, uint256 timestamp) onlyPoolToken nonReentrant public override {

        uint256 old_amount = holderInfo[0];
        uint256 new_amount = holderInfo[1];
        uint256 principal = holderInfo[2];

        uint256 difference = new_amount.sub(old_amount);

        require(difference>=minStakingAmount,"amount should > minStakingAmount");

        if(_timestamps[account] == 0) {

            tokenHolderIds.push(account);

        }

        joveVault.deposit(principal);

        uint256 period = expireTimestamp.sub(timestamp);

        uint256 stakingTimeAmount = difference.mul(period).mul(period);

        _totalStakingTimeAmount = _totalStakingTimeAmount.add(stakingTimeAmount);

        _tokenStakingTimeAmount[account] = _tokenStakingTimeAmount[account].add(stakingTimeAmount);

        uint256 timestamp2 = _tokenStakingTimeAmount[account].div(new_amount);

        timestamp2 = sqrt(timestamp2);

        _timestamps[account]=timestamp2;

    }



    function removeTokenHolder(address account, uint256[] memory holderInfo, uint256 stakingtimeamount) onlyPoolToken nonReentrant public override{ 

        uint256 old_amount = holderInfo[0];
        uint256 new_amount = holderInfo[1];
        uint256 principal = holderInfo[2];

        uint256 period = expireTimestamp.sub(_timestamps[account]);

        if(new_amount == 0) {

            _timestamps[account] = 0;

            //tokenHolderIds.pop(account);

        }

        joveVault.withdraw(old_amount.sub(new_amount));

        uint256 stakingTimeAmount = _tokenStakingTimeAmount[account];

        require(stakingTimeAmount == stakingtimeamount, "stakingTimeAmount is wrong");

        uint256 diffstakingTimeAmount = principal.mul(period).mul(period);

        _totalStakingTimeAmount = _totalStakingTimeAmount.sub(diffstakingTimeAmount);

        _tokenStakingTimeAmount[account] = stakingtimeamount.sub(diffstakingTimeAmount);

    }



    function  updateDependentContractAddress() public override{

        _priceMetaInfoDb=PriceMetaInfoDB(register.getContract("MIDB"));

        //stakingPoolToken=IStakingPoolToken(register.getContract("SKPT"));

        //require(address(stakingPoolToken)!=address(0),"updateDependentContractAddress - staking pool token does not init");

        //_tokenRegister=ERC20TokenRegister(register.getContract("TKRG"));

    }



    function setStakingPoolToken(address stakingpoolTokenAddr) onlyOwner public {

    	require(stakingpoolTokenAddr != address(0), "stakingpoolTokenAddr must not 0x");

    	stakingPoolToken=IStakingPoolToken(stakingpoolTokenAddr);

    }

    

    function calcPremiumsRewards(uint256 accumulateTimeStampsRewards) view public override returns(uint256){

        if (_totalStakingTimeAmount == 0) {

            return 0;

        }

        return totalPoolTokenPremiums.mul(accumulateTimeStampsRewards).div(_totalStakingTimeAmount); 

    }

    

    function updataPremiumsRewards(uint256 reward) onlyProductToken public override{

        totalPoolTokenPremiums = totalPoolTokenPremiums.add(reward);

    }

    

    function deletePremiumsRewards(uint256 reward) onlyProductToken public override{

        totalPoolTokenPremiums = totalPoolTokenPremiums.sub(reward);

    }    



    function totalNeedPayFromStaking() view public override returns(uint256){

        return _totalNeedPayFromStaking;

    }



    function totalRealPayFromStaking() view public override returns(uint256){

        return _totalRealPayFromStaking;

    }



    function payAmount(address productTokenAddr) view public override returns(uint256){

        return _payAmount[productTokenAddr];

    }



    function productTokenExpireTimestamp(address productAddr) view public override returns(uint256) {

        if(_claimexpireTimestamp.inserted[productAddr]) {

            return _claimexpireTimestamp.get(productAddr);

        }else{

            return expireTimestamp;

        }

    }



    function hasClaimQuantity() view public returns(address[] memory, uint256[] memory, uint256[] memory) { //是否有需要进入观察期的保单 

        address[] memory productTokenAddrArray;

        uint256[] memory amountsArray;

        uint256[] memory expireTimestampsArray;

        

        require(_claimQuantity.size() == _claimexpireTimestamp.size());

        

        for (uint i = 0; i < _claimQuantity.size(); i++) {

            address key = _claimQuantity.getKeyAtIndex(i);

            productTokenAddrArray[i] = key;

            amountsArray[i] = _claimQuantity.get(key);

            expireTimestampsArray[i] = _claimexpireTimestamp.get(key);

        }

        

        return (productTokenAddrArray, amountsArray, expireTimestampsArray);

    }



    function getTokenAddress() view public override returns(address) {

    	return tokenAddress;

    }



    function getTotalStakingTimeAmount() view public returns(uint256) {

    	return _totalStakingTimeAmount;

    }

    function setNeedPayFlagAll(bool[] memory needPay, address[] memory productTokenAddr, uint256[] memory timestamp) onlyController nonReentrant public override{
        for(uint i = 0; i < needPay.length; ++i) {
            setNeedPayFlag(needPay[i], productTokenAddr[i], timestamp[i]);
        }
    }

    function setNeedPayFlag(bool needPay, address productTokenAddr, uint256 timestamp) onlyOwnerAndController nonReentrant public override{

        IJoveProductToken productToken = IJoveProductToken(productTokenAddr);

        if(needPay) {

            productToken.approvePaid();

        }else{

            productToken.rejectPaid();

            uint256 totalPremiums = tokenAddress.balanceOfERC20(address(this));

            joveVault.deposit(totalPremiums);

        }

        uint256 totalSellQuantity = _claimQuantity.get(productTokenAddr);

        if(needPay && totalSellQuantity>0) { 

            require(timestamp <= _claimexpireTimestamp.get(productTokenAddr));

            needPayFlag =  needPay;

            claimEnable[productTokenAddr] = true;

            //uint256 totalPremiums = _tokenRegister.getTokenBalance(coinName, address(this));

            uint256 totalPremiums = tokenAddress.balanceOfERC20(address(this));

            uint256 totalNeedPayAmount = totalSellQuantity.sub(totalPremiums);

            uint256 totalRealPayAmount = joveVault.balance();

            if(totalRealPayAmount<=totalNeedPayAmount) {

                _totalNeedPayFromStaking = totalRealPayAmount;

            }else{

                _totalNeedPayFromStaking = totalNeedPayAmount;   

            }

    

            if(_totalNeedPayFromStaking>0){

                //address tokenAddress = _tokenRegister.getToken(coinName);

                joveVault.withdraw(_totalNeedPayFromStaking);

                tokenAddress.transferERC20(address(stakingPoolToken),totalPremiums);

                _totalPremiumsAfterClose=totalPremiums;

                stakingPoolToken.bookkeepingFromPool(_totalNeedPayFromStaking.add(_totalPremiumsAfterClose), productTokenAddr);

            }

            updatePayAmount(productTokenAddr);

        }

    }



    function updatePayAmount(address productTokenAddr) public {

        require(claimEnable[productTokenAddr], "productToken is not claimed");

        //uint256 totalAmount = _tokenRegister.getTokenBalance(coinName, address(this));

        uint256 totalAmount = tokenAddress.balanceOfERC20(address(this));

        uint256 totalSellQuantity = _claimQuantity.get(productTokenAddr);

        if(totalSellQuantity > 0) {

            _payAmount[productTokenAddr] = totalAmount.add(_totalNeedPayFromStaking).add(_totalPremiumsAfterClose).div(totalSellQuantity);

        }else{

            _payAmount[productTokenAddr] = 0;

        }

        if (totalAmount>0){

            //address tokenAddress = _tokenRegister.getToken(coinName);

            _totalPremiumsAfterClose=_totalPremiumsAfterClose.add(totalAmount);

            tokenAddress.transferERC20(address(stakingPoolToken),totalAmount);

            stakingPoolToken.bookkeepingFromPool(totalAmount, productTokenAddr);

        }

        

    }

    

    function getTotalPoolTokenPremiums() view public returns(uint256) {

    	return totalPoolTokenPremiums;

    }



    function productNeedClaim(uint256 quantity, uint256 expireTimestamp, address productAddr) external override onlyController{

        _claimQuantity.set(productAddr, quantity); 

        _claimexpireTimestamp.set(productAddr, expireTimestamp);

        _totalClaimQuantity = _totalClaimQuantity.add(quantity);    			

    }

/*

    function closeProduct() external onlyOwner {

        for(uint256 i=0;i < productTokenAddrs.length();++i) {

            address productAddr = productTokenAddrs.at(i);

            IJoveProductToken productToken = IJoveProductToken(productAddr);

            productToken.isClaim();

            if(productToken.isClaim()) {

                uint256 quantity = productToken.totalSellQuantity();

                _claimQuantity.set(productAddr, quantity); 

                _claimexpireTimestamp.set(productAddr, productToken.getExpireTimestamp());

                _totalClaimQuantity = _totalClaimQuantity.add(quantity);

            }else{

                productToken.rejectPaid();

            }

        }

    } 

*/

        

    function productToken(address productAddr) external view override returns(IJoveProductToken){

        require(productAddr != address(0), "product address is not 0");

        IJoveProductToken productToken = IJoveProductToken(productAddr);

        return productToken;

    }



    function queryAndCheckClaimAmount(address userAccount, address productTokenAddr) view external override returns(uint256,uint256/*token balance*/){

        require(claimEnable[productTokenAddr],"claim not enable");

        require(_payAmount[productTokenAddr]>0,"no money for claim");

        IJoveProductToken productToken = IJoveProductToken(productTokenAddr);

        uint256 productTokenQuantity = productToken.balanceOf(userAccount);

        return (productTokenQuantity.mul(_payAmount[productTokenAddr]),productTokenQuantity);

    }

}
