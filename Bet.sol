pragma solidity ^0.4.24;

import "./DateTime.sol";
import "./Ownable.sol";

contract Bet is DateTime,Ownable{
  struct BetPerson{
    uint  betTime; //投注时间
    uint  value;  //投的注数
    uint  signTime; //签到时间
  }

  uint constant DAYTIME = 86400; //一天的时间转换成秒
  uint constant TIME_LAG = 28800;//时差

  event NewBeter(address _address, uint _value); //有新投注时触发
  event NewBeterLog(address _address, uint _value); //发奖到个人时触发
  event Signing(address _address); //签到触发
  event Lottery(address _owner); //发奖完毕触发

  //每期信息的封装
  struct lotteryInfo {
    uint totalLuckypool;  //每一期的奖池金额
    uint userCount;       //投注用户数量
    uint userSignCount;   // 签到用户数量
    uint betSignCount;   // 中奖的注数
  }

  mapping(uint => mapping(address => BetPerson[])) totalBetInfo; //总的投注信息 20180831=>0x121..=>BetPerson
  mapping(uint => lotteryInfo) totalLotteryInfo; //对每期的信息进行封装
  mapping(uint => address[]) awardPool; //每期中奖的地址
   
   //把时间戳转化为 20180831 的格式，方便查询
   function getTimetoDay(uint timestamp) private pure returns(uint){
    uint _year = getYear(timestamp + TIME_LAG);
    uint _month = getMonth(timestamp + TIME_LAG);
    uint _day = getDay(timestamp + TIME_LAG);
    uint  total = _year * 10000 + _month * 100 + _day;
    return total;
  }
  //把时间戳转化为 162934 的格式，方便看具体时间
  function getTimetoSecond(uint _timestamp) private pure returns(uint){
    uint _hour = getHour(_timestamp + TIME_LAG);
    uint _munite = getMinute(_timestamp + TIME_LAG);
    uint _second = getSecond(_timestamp + TIME_LAG);
    uint tosecond = _hour * 10000 + _munite * 100 + _second;
    return tosecond;
  }
  
  //投注
  function newBet() public payable {
    uint hour = getHour(now + TIME_LAG);
    //要求每注1个 1个Luckywin，可以投多注，投注时间为每天 10：00---24：00
    require(msg.value >= 1 && hour > 10 && hour < 24);
    
    //期数 20180831
    uint period= getTimetoDay(now);
    //新的投注对象
    BetPerson memory rebetperson = BetPerson(getTimetoSecond(now), msg.value, 61);
    totalBetInfo[period][msg.sender].push(rebetperson);
    //奖池增加 msg.value
    totalLotteryInfo[period].totalLuckypool+=msg.value;
    if (totalBetInfo[period][msg.sender].length == 1){
        //如果第一次投注，这期的投注人数+1
        totalLotteryInfo[period].userCount++;
    }
     emit NewBeter(msg.sender,msg.value);
  }
  //签到 
  function sign() public {
   //签到时间规定为凌晨1-7点，由于是第二天，减去一天的时间
   uint _signPeriod = now - DAYTIME;
   uint signPeriod = getTimetoDay(_signPeriod);
   uint hour = getHour(now + TIME_LAG);
   require(totalBetInfo[signPeriod][msg.sender].length > 0 && hour > 1 && hour < 7);
  
  //用户签到把用户所有投注对象的时间重置到此时。
   for (uint num = 0; num < totalBetInfo[signPeriod][msg.sender].length; num++){
     totalBetInfo[signPeriod][msg.sender][num].signTime= now;
     //这期的中奖注数 +value
     totalLotteryInfo[signPeriod].betSignCount += totalBetInfo[signPeriod][msg.sender][num].value;
    }
    //这一期的中奖用户数量 +1
    totalLotteryInfo[signPeriod].userSignCount++;
    //把中奖用户地址添加到 这期中奖名单里面
    awardPool[signPeriod].push(msg.sender);
    emit Signing(msg.sender);
  } 
  
  //系统发奖
  function award() public payable  onlyOwner {
    //发奖时间为9点，发奖人为合约创建者
   require(getHour(now + TIME_LAG) > 9 && msg.sender==owner);
   //发奖的期数为昨天的
   uint _awardPeriod = now - DAYTIME;
   uint awardPeriod = getTimetoDay(_awardPeriod);
   //首先遍历上期中奖用户
   for (uint index = 0; index < awardPool[awardPeriod].length ; index++) {
       //给此用户发多少奖励
       uint myPrize = computerMyPrize(awardPool[awardPeriod][index], awardPeriod);
       awardPool[awardPeriod][index].transfer(myPrize);
       emit NewBeterLog(awardPool[awardPeriod][index] , myPrize);
     }
     //发奖完毕
      emit Lottery(msg.sender);
  }
  
  //计算给我的奖励是多少
  function computerMyPrize(address wineraddress, uint awardtime ) private view returns (uint) {
    uint _computertime = now - DAYTIME;
    uint computertime = getTimetoDay(_computertime);
    //计算每一注奖励多少
    uint perPrize = totalLotteryInfo[computertime].totalLuckypool / totalLotteryInfo[computertime].betSignCount;
    uint countmyprize = 0;
    //找出中奖的人中了多少注
    for (uint indexs = 0; indexs < totalBetInfo[awardtime][wineraddress].length; indexs++) {
      countmyprize += totalBetInfo[awardtime][wineraddress][indexs].value;
    }
    //计算奖金
    uint totalMyprize = perPrize * countmyprize;
    return totalMyprize;
  }
  
  //查看指定期数的情况
  function viewBetInfo(uint viewtime) public view returns (uint _totalaward,uint _betplayer,uint _totalbet) {
   _totalaward = totalLotteryInfo[viewtime].totalLuckypool;
   _betplayer = totalLotteryInfo[viewtime].userCount;
   return (_totalaward,_betplayer,_totalaward);
  } 
  
  //用户查看指定自己投注
  function viewMyBetInfo(uint period, uint index) public view returns (uint  betTimes, uint values, bool  isAwards, uint prizes){
    //用户投注的第一注在数组的下标为0
    uint indexs = index - 1;
    betTimes = totalBetInfo[period][msg.sender][indexs].betTime;
    values = totalBetInfo[period][msg.sender][indexs].value;
   //用户中奖把中奖信息计算并返回
   if (totalBetInfo[period][msg.sender][index].signTime != 61) {
     uint perPrizetoplayer = totalLotteryInfo[period].totalLuckypool / totalLotteryInfo[period].betSignCount;
     isAwards = true;
     prizes = values * perPrizetoplayer;
     return (betTimes, values, isAwards, prizes);
   }else{
       //返回不中奖信息
       return (betTimes,values,false,0);
   }
   
   
  }
  
  function () public payable {
      
  }

}