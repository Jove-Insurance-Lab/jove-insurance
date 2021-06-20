//SPDX-License-Identifier: SimPL-2.0

pragma solidity >=0.6.0 <0.7.0;

pragma experimental ABIEncoderV2;


import "./@openzeppelin/token/ERC721/ERC721.sol";

import "./@openzeppelin/access/Ownable.sol";

import "./@openzeppelin/math/SafeMath.sol";

import "./@openzeppelin/math/Math.sol";

import "./@openzeppelin/token/ERC20/SafeERC20.sol";

import "./@openzeppelin/token/ERC20/ERC20.sol";

import "./@openzeppelin/utils/ReentrancyGuard.sol";



import "./IUpgradable.sol";

import "./IStakingPool.sol";

import "./PriceMetaInfoDB.sol";

import "./CompatibleERC20.sol";

import "./flashloan/IFlashLoanReceiver.sol";



struct CoinHolder {

    uint256 amount;

    uint256 beginTimestamp;

    uint256 stakingTimeRewards;

    string coin;

    address pool;

}



contract StakingTokenHolder

{

    using SafeMath for uint256;

    mapping(address=>CoinHolder) public _coinHolders;

    

    address _operator;



    function setOperator(address addr) public {

        require(_operator==address(0), "only once");

        _operator = addr;

    }



    modifier onlyOperator() {

        require(_operator == msg.sender, "Ownable: caller is not the operator");

        _;

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



    function canReleaseTokenHolderAmount(address account, uint256 supply, uint256 balance) view public returns(uint256) {

        CoinHolder storage holder = _coinHolders[account];

        IStakingPool pool = IStakingPool(holder.pool);

        uint256 amount = holder.amount;

        uint256 remainingPrincipal = amount.mul(balance).div(supply);

        uint256 poolCapacity = pool.calculateCapacity();

        if(poolCapacity < remainingPrincipal){

            return poolCapacity;

        }else{

            return remainingPrincipal;

        }

    }



    function calcPremiumsRewards(address account) view public returns(uint256){

        CoinHolder storage holder = _coinHolders[account];

        uint256 rewards=0;

        IStakingPool pool = IStakingPool(holder.pool);

        rewards=rewards.add(pool.calcPremiumsRewards(holder.stakingTimeRewards));

        return rewards;

    }

    

    function getTokenHolderPool(address account) view public returns(address){

        CoinHolder storage holder = _coinHolders[account];

        return holder.pool;

    }    



    function getTokenHolderBeginTimestamp(address account) view public returns(uint256){   

        CoinHolder storage holder=_coinHolders[account];



        return holder.beginTimestamp;

    }  

    

    function getStakingTimeRewards(address account) view public returns(uint256) {

    	CoinHolder storage holder=_coinHolders[account];

    	return holder.stakingTimeRewards;

    }



    function set(address[] memory addrs, uint256 amount, uint256[] memory timestamp, string memory coinName) onlyOperator public{

        uint256 beginTimestamp = timestamp[0];

        uint256 expiretime = timestamp[1];

        uint256 period = expiretime.sub(beginTimestamp);

        uint256 stakingTimeRewards = amount.mul(period).mul(period);

        address account = addrs[0];

        address poolAddr = addrs[1];

        

        _coinHolders[account]=CoinHolder(amount,beginTimestamp,stakingTimeRewards,coinName,poolAddr);

    }

    

    function updateHolderInfo(address account, uint256 amount, uint256[] memory timestamp) onlyOperator public{

        CoinHolder storage holder=_coinHolders[account];

        uint256 old_amount = holder.amount;

        uint256 stakingTimeRewards = holder.stakingTimeRewards;

        uint256 beginTimestamp = timestamp[0];

        uint256 expiretime = timestamp[1];

        

        if(old_amount > amount) {

            uint256 difference = old_amount.sub(amount);

            uint256 period = expiretime.sub(holder.beginTimestamp);

            stakingTimeRewards = stakingTimeRewards.sub(difference.mul(period).mul(period));

        } else {

            uint256 difference = amount.sub(old_amount);

            uint256 period = expiretime.sub(beginTimestamp);

            stakingTimeRewards = stakingTimeRewards.add(difference.mul(period).mul(period));

            uint256 timestamp2 = stakingTimeRewards.div(amount);

            timestamp2 = sqrt(timestamp2);

            holder.beginTimestamp =  timestamp2;

        }

        holder.amount = amount;

    }

    



    function getHolderStakingTimeRewards(address account) view public returns(uint256){

        CoinHolder storage holder=_coinHolders[account];

        return holder.stakingTimeRewards;          

    }

    

    function initSponsor() external {

        ISponsorWhiteListControl SPONSOR = ISponsorWhiteListControl(address(0x0888000000000000000000000000000000000001));

        address[] memory users = new address[](1);

        users[0] = address(0);

        SPONSOR.addPrivilege(users);

    }  

    

}



contract StakingPoolToken is ERC20, IUpgradable, ReentrancyGuard

{

    using SafeMath for uint256;

    using CompatibleERC20 for address;

    using SafeERC20 for IERC20;

    

    address[] private accountArray;

    StakingTokenHolder public _coinHolders;

    mapping(address=>string) _pool;

    address public poolAddr;

    PriceMetaInfoDB  _priceMetaInfoDb;

    address private tokenAddress;

    uint256 public expiretime;

    

    mapping(address/*productTokenAddr*/=>uint256) _compensation;

    uint256 _totalCompensation;

    

    constructor(address coinHolder, string memory tokenName, string memory symbolName, address _tokenAddress) ERC20(tokenName, symbolName) ReentrancyGuard() public{

        _coinHolders = StakingTokenHolder(coinHolder);

        _coinHolders.setOperator(address(this));

        tokenAddress = _tokenAddress;

    }    



    function  updateDependentContractAddress() public override{

        _priceMetaInfoDb=PriceMetaInfoDB(register.getContract("MIDB"));

        //_tokenRegister=ERC20TokenRegister(register.getContract("TKRT"));

    }



    function isPool(address pool_address) view public returns(bool){

        return bytes(_pool[pool_address]).length!=0;

    }   

    

    modifier onlyPool(){

        require(isPool(_msgSender()),"Unknown staking pool");

        _;

    }

 

    function stringToBytes8(string memory source) view internal returns(bytes8 result) {

    	assembly{

    	    result := mload(add(source, 8))

    	}

    }

    

    function isContract(address addr) public returns(bool) {

        uint size;

        assembly { 

            size := extcodesize(addr)

        }

        return size > 0;    

    }



    

    function deposite(address account, uint256 principal, uint256 supply, uint256 balance, address pool_address) whenNotPaused external {

        require(principal>0, "principal must > 0");

        require(tokenAddress.allowanceERC20(account,address(this))>=principal,"No enough allowance for new token holder");

        tokenAddress.transferFromERC20(account,address(this),principal);

        uint256 beginTimestamp = now;

        uint256 amount = principal.mul(supply).div(balance);

        uint256[] memory timestamp = new uint256[](2);

        timestamp[0] = beginTimestamp;

        timestamp[1] = expiretime;

        address[] memory addrs = new address[](2);

        addrs[0] = account;

        addrs[1] = pool_address;

        IStakingPool pool = IStakingPool(pool_address);

        

        if(balanceOf(_msgSender()) <= 0) {

            uint256[] memory holderInfo = new uint256[](3);

            holderInfo[0] = 0;

            holderInfo[1] = amount;

            holderInfo[2] = principal;

            _coinHolders.set(addrs, amount, timestamp, _pool[poolAddr]);

            pool.updateTokenHolder(account, holderInfo, beginTimestamp); 

        } else {

            uint256 old_amount = balanceOf(account);

            uint256 new_amount = old_amount.add(amount);

            uint256[] memory holderInfo = new uint256[](3);

            holderInfo[0] = old_amount;

            holderInfo[1] = new_amount;

            holderInfo[2] = principal;

            _coinHolders.updateHolderInfo(account, new_amount, timestamp);

            pool.updateTokenHolder(account, holderInfo, beginTimestamp);   

        }

        _mint(account, amount);

    }



    function canReleaseTokenHolderAmount(address account, uint256 supply, uint256 balance) view public returns(uint256) {

        //uint256 amount = balanceOf(account);

    	return _coinHolders.canReleaseTokenHolderAmount(account, supply, balance);

    }

    

    function withdraw(address account, uint256 amount, uint256 supply, uint256 balance, address pool_address) whenNotPaused external {

        require(amount>0, "amount must > 0");  

        uint256 withdrawAmount = canReleaseTokenHolderAmount(account, supply, balance);

        require(withdrawAmount >= amount, "the amount to withdraw is too large");
        
        uint256 beginTimestamp = now;
        
        uint256[] memory timestamp = new uint256[](2);

        timestamp[0] = beginTimestamp;

        timestamp[1] = expiretime;

        uint256 old_amount = balanceOf(account);

        _burn(account, amount);

        uint256 money = amount.mul(balance).div(supply);

        IStakingPool pool = IStakingPool(pool_address);

        uint256 new_amount = balanceOf(account);

        _coinHolders.updateHolderInfo(account, new_amount, timestamp);

        uint256 stakingtimerewards = _coinHolders.getStakingTimeRewards(account);
        
        uint256[] memory holderInfo = new uint256[](3);

        holderInfo[0] = old_amount;

        holderInfo[1] = new_amount;

        holderInfo[2] = money;

        pool.removeTokenHolder(account, holderInfo, stakingtimerewards);   

        tokenAddress.transferERC20(account,money);

    }



    function claim(address pool_address, address productTokenAddr, address userAddr) nonReentrant whenNotPaused public{

        require(isPool(pool_address),"unknown staking pool");

        IStakingPool pool=IStakingPool(pool_address);

        (uint256 amount, uint256 tokenBalance) = pool.queryAndCheckClaimAmount(userAddr, productTokenAddr);

        require(amount>0,"not claim");

        require(_compensation[productTokenAddr]>=amount,"amount must < pool's pay amount");

        _compensation[productTokenAddr]=_compensation[productTokenAddr].sub(amount);

        _totalCompensation = _totalCompensation.sub(amount);

        //address erc20token = _tokenRegister.getToken(_pool[poolAddr]); 

        tokenAddress.transferERC20(userAddr,amount);

        pool.productToken(productTokenAddr).burn(userAddr,tokenBalance);

    }

    



    function calcPremiumsRewards(address account, uint256 supply, uint256 balance) view public returns(uint256, uint256){

        uint256 money = _coinHolders.calcPremiumsRewards(account);

        return (money.mul(supply).div(balance), money);

    }    

    

    function harvestPremiums(uint256 supply, uint256 balance) whenNotPaused public{

        IStakingPool pool = IStakingPool(poolAddr);

        uint256 rewards = 0;

        for(uint i = 0; i < accountArray.length; ++i) {

            //address poolAddr = _coinHolders.getTokenHolderPool(tokenId);

            //address erc20token = _tokenRegister.getToken(_pool[poolAddr]);

            address account = accountArray[i];

            (uint256 reward, uint256 money) = calcPremiumsRewards(account, supply, balance);

            if(reward > 0) {

                _mint(account, reward);

                rewards = rewards.add(money);

            }

        }

        pool.deletePremiumsRewards(rewards);

    }



    function registerStakingPool(address pool_address,string memory poolName) onlyOwner public {

        require(!isPool(pool_address),"Staking pool has been already registered");

        _pool[pool_address]= poolName;

        poolAddr = pool_address;

    }



    function unregisterStakingPool(address pool_address) onlyOwner public{

        require(isPool(pool_address),"Staking pool has not been registered");

        delete _pool[pool_address];

    }

}
