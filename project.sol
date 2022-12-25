//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./ERC20.sol";

contract dbHandler {
  bytes32 reviewCID; 
  bytes32 usersCid;
  event postReview (string review, uint rating, uint reviewID ,address user, address serviceProvider);
  event dbContractAddr(address dbAddress);
  event upVote(uint reviewId, address serviceProvider, address user);
  event downVote (uint reviewId, address serviceProvider, address user);
  event updateRep (uint upvotes, uint downvotes,uint reviews, address user);

  constructor(){
    emit dbContractAddr(address(this));
  }

  function getReview() public view returns (bytes32){
    return reviewCID;
  }
  function uploadReview(string memory _review,uint _rating,uint reviewId, address user, address serviceProvider) public  {
  
   emit postReview(_review, _rating, reviewId, user, serviceProvider);
  }
  function upVoteReview(uint reviewId, address serviceProvider, address user) public  {
    emit upVote(reviewId, serviceProvider, user);
  }
  function downVoteReview(uint reviewId, address serviceProvider, address user) public  {
    emit downVote(reviewId, serviceProvider, user);
  }
  function updateReputation (uint upvotes, uint downvotes,uint reviews, address user) public  {
    emit updateRep(upvotes, downvotes, reviews, user);
  }

  function giveReward (address user,uint reputation, address sp) public  {  //called by the script after the user posts a review
    ServiceProvicer(payable(sp)).rewardUser(user,reputation);
  }

  function setReview(bytes32 _reviewCID) public {
    reviewCID = _reviewCID;
  }
  function setUsers(bytes32 _usersCid) public {
    usersCid = _usersCid;
  }


}

contract MainContract {
  // The second contract
  mapping(address => mapping(address => uint)) activeContracts;
  dbHandler dbAddr;
  event contractDeployed(address contract_addr);
  constructor () {
    dbHandler db = new dbHandler();
    dbAddr = db;
  }

  function registerFunction(string memory name, string memory symbol, uint _amount) public payable  returns (address) {
    
    require(msg.value > 0, "You must deposit some ETH to mint new tokens");
      
    ServiceProvicer instance = new ServiceProvicer(msg.sender,dbAddr,name,symbol,_amount);
    activeContracts[msg.sender][address(instance)] = msg.value;
    emit  contractDeployed(address (instance));

    // Return the address of the second contract
    return address(instance);
  }

  function updateReputation (uint upvotes, uint downvotes,uint reviews ) public  returns (uint){
    uint256 diff = 0;
    if (upvotes > downvotes){
      diff = upvotes - downvotes;
      diff = diff*10;
    }
    uint256 review_num = reviews*10;
    diff = calculate(diff, 70);
    reviews = calculate(review_num,30);
    dbAddr.updateReputation(upvotes, downvotes, reviews, msg.sender);
    return diff+reviews;
  }

  function calculate(uint256 amount, uint256 percentage) public pure returns (uint256) {
        uint256 bps = percentage*100;
        require((amount * bps) >= 10000,"percentage err");
        return (amount * bps) / 10000;
  }
}

contract ServiceProvicer  is ERC20{
    mapping(uint=>uint[]) discountMap;
   // uint [] discount_array; 
    event EthRecived(uint val);
    address [] current_customers;
    uint reviewId;
    dbHandler dbAddr;
    mapping(uint => uint[]) rewardTiers;
    

    receive () external payable {
        emit EthRecived(msg.value);
    }

    address owner;
    constructor(address _owner,dbHandler _dbAddr,string memory name, string memory symbol, uint _amount)  {
   
        owner = _owner;
        dbAddr = _dbAddr;
        mint(_owner,name,symbol,_amount);
    }

    function getAddr () public view returns (address) {
        return  owner;
    }

    function getBalance() public view returns (uint){
     uint bal; 
     bal =  balance(msg.sender);
     return bal ;
    }

  function payment (uint discount_tokens) payable public  {
    uint256 returnAmount = 0;
    if (discount_tokens > 0){
      for (uint i = 1; i>0 ; i++){
        uint[] memory arr =  discountMap[i];
        if (arr.length == 0){
          break;
        }
        if (discount_tokens >= arr[0] ){
          returnAmount = arr[1];
        }
        else {
          break;
        }
      }
      (bool sent,) = payable(msg.sender).call{value: returnAmount*1 gwei}("");
      require(sent, "Failed to send Ether");

      if (returnAmount != 0){
        transfer (msg.sender,owner,discount_tokens);
      }

    }
    (bool sent2,) = payable(owner).call{value: returnAmount*1 gwei}("");
    require(sent2, "Failed to send Ether to owner");
    allowReview(msg.sender);
      
  }

  function setDiscount(uint tier,uint discount,uint amount) public {  //input discount as 0.1,0.2,0.3 for 10,20,30 percent discount
    require(msg.sender == owner, "Only the service provider can call this function");
    discountMap[tier] = [amount,discount];
    //map[tier] = > token_amount, return eth

  }

  function transferTo(address x,uint amount) public {
    require(msg.sender == owner, "Only the service provider can call this function");
    transfer(msg.sender, x,amount );
  }

  function allowReview (address x) public   {
    require(msg.sender == owner, "Only the service provider can call this function");
    current_customers.push(x);
  }

  function postReview (string memory review, uint rating) public {
    
    int index = -1;
    for (uint i = 0; i<current_customers.length ; i++){
      if (current_customers[i] == msg.sender){
        index = int(i);
        break;
      }
    }
    require(index != -1, "Not eligible to post review");
    delete current_customers[uint(index)];
    dbAddr.uploadReview(review,rating,reviewId,msg.sender,address(this));
    reviewId++;
      
  }
  
  function upVote(uint _reviewId) public {
    dbAddr.upVoteReview(_reviewId,address(this),msg.sender);
  }

  function downVote(uint _reviewId) public {
    dbAddr.downVoteReview(_reviewId,address(this),msg.sender);
  }

  function rewardUser (address user, uint reputation) public {
    require(msg.sender == address(dbAddr), "Only the database contract can call this function");
    uint rewardAmount;
    for (uint i = 1; i>0 ; i++){
        uint[] memory arr =  discountMap[i];
        if (arr.length == 0){
          break;
        }
        if (reputation >= arr[0] ){
          rewardAmount = arr[1];
        }
        else {
          break;
        }
      }
    if (rewardAmount != 0){
      transfer(owner,user,rewardAmount);
    }
    
  }

  function setReward (uint tier,uint reputation, uint reward) public {  
    require(msg.sender == owner, "Only the service provider can call this function");
    rewardTiers[tier] = [reputation,reward];
    //map[tier] = > reputation, reward

  }

}