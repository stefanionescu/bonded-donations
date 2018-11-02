pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./BondingCurve.sol";
import "./Token.sol";

contract Logic is Ownable {
    using SafeMath for uint256;

    // Keep the balances of ERC20s
    address public tokenContract;

    // Bonding curve ETH
    address public bondingContract;

    // Charity address
    address public charityAddress;

    // KYC flag
    bool public kycEnabled;

    // Minimum ETH balance for valid bonding curve
    uint256 public minEth;

    event LogTokenContractChanged
    (
        address byWhom,
        address oldContract,
        address newContract
    );

    event LogBondingContractChanged
    (
        address byWhom,
        address oldContract,
        address newContract
    );

    event LogMinEthChanged
    (
        address byWhom,
        uint256 oldAmount,
        uint256 newAmount
    );

    event LogCharityAddressChanged
    (
        address byWhom,
        address oldAddress,
        address newAddress
    );

    event LogDonationReceived
    (
        address byWhom,
        uint256 amount
    );

    event LogCharityAllocationSent(
        uint256 amount,
        address indexed account
    );

    modifier kycCheck() {
        if (kycEnabled) {
            // require whitelisted address (see Bloom docs?)
        }
        _;
    }

    modifier minimumBondingBalance() {
        require(bondingContract.balance >= minEth, "Not enough ETH in bonding contract");
        _;
    }

    /**
    * @dev donation function splits ETH, 90% to charityAddress, 10% to fund bonding curve
    */
    function donate() public payable returns (bool) {
        require(charityAddress != address(0), "Charity address is not set correctly");
        require(msg.value > 0, "Must include some ETH to donate");

        // Make ETH distributions
        uint256 multiplier = 100;
        uint256 charityAllocation = (msg.value).mul(90); // 90% with multiplier
        uint256 bondingAllocation = (msg.value.mul(multiplier)).sub(charityAllocation).div(multiplier);
        sendToCharity(charityAllocation.div(multiplier));

        bondingContract.transfer(bondingAllocation);

        // Mint the tokens - 10:1 ratio (e.g. for every 1 ETH sent, you get 10 tokens)
        bool minting = Token(tokenContract).mintToken(msg.sender, (msg.value).mul(10));
        emit LogDonationReceived(msg.sender, msg.value);

        return minting;
    }
    
    // TODO: - DAI integration: buy DAI with ETH, store in charityAddress
    function sendToCharity(uint256 _amount) internal {
        // this should auto convert to DAI
        // look into OasisDEX or Bancor on-chain tx
        charityAddress.transfer(_amount);
        emit LogCharityAllocationSent(_amount, msg.sender);
    }

    /**
    * @dev sell function for selling tokens to bonding curve
    */
    function sell(uint256 _amount) public minimumBondingBalance returns (bool) {
        uint256 tokenBalanceOfSender = Token(tokenContract).balanceOf(msg.sender);
        require(_amount > 0 && tokenBalanceOfSender >= _amount, "Amount needs to be > 0 and tokenBalance >= amount to sell");

        // calculate sell return
        uint256 amountOfEth = calculateReturn(_amount, tokenBalanceOfSender);

        // burn tokens
        Token(tokenContract).burn(msg.sender, _amount);

        // sendEth to msg.sender from bonding curve
        BondingCurve(bondingContract).sendEth(amountOfEth, msg.sender);
    }

    /**
    * @dev calculate how much ETH should be returned for a certain amount of tokens
    */
    function calculateReturn(uint256 _sellAmount, uint256 _tokenBalance) public view returns (uint256) {
        require(_tokenBalance >= _sellAmount, "User trying to sell more than they have");
        uint256 supply = Token(tokenContract).getSupply();

        // For EVM accuracy
        uint256 multiplier = 10**18;

        if (coolDownPeriod(msg.sender) <= 0) {
            // Price = (Portion of Supply ^ ((1/4) - Portion of Supply)) * (ETH in Pot / Token supply)
            // NOT YET WORKING (problem with decimal precision for exponent)
            uint256 portionOfSupply = (_tokenBalance.mul(multiplier).div(supply));
            uint256 exponent = ((multiplier.div(multiplier).div(4*multiplier)).sub(portionOfSupply)).div(multiplier);
            uint256 price = ((portionOfSupply**exponent).mul((bondingContract.balance).div(supply))).div(multiplier);
            
            uint256 redeemableEth = price.mul(_sellAmount);
            return redeemableEth;
        } else {
            return 0;
        }
    }

    // !! TODO: - set cooldown time period before selling
    // returns uint256 in number of hours
    function coolDownPeriod(address _tokenHolder) public view returns (uint256) {
        // something like today - (day of buying + 7 days)
        // todo when minting tokens
        return 0;
    }

    // KYC logic - stretch goals
    // add donator to whitelist
    // see Bloom docs

    // only owner

    /**
    * @dev Set both the 'logicContract' and 'bondingContract' to different contract addresses in 1 tx
    */
    function setTokenAndBondingContract(address _tokenContract, address _bondingContract) public onlyOwner {
        setTokenContract(_tokenContract);
        setBondingContract(_bondingContract);
    }

    /**
    * @dev Set the 'logicContract' to a different contract address
    */
    function setTokenContract(address _tokenContract) public onlyOwner {
        address oldContract = tokenContract;
        tokenContract = _tokenContract;
        emit LogTokenContractChanged(msg.sender, oldContract, _tokenContract);
    }

    /**
    * @dev Set the 'bondingContract' to a different contract address
    */
    function setBondingContract(address _bondingContract) public onlyOwner {
        address oldContract = bondingContract;
        bondingContract = _bondingContract;
        emit LogBondingContractChanged(msg.sender, oldContract, _bondingContract);
    }

    /**
    * @dev Set the 'minEth' amount
    */
    function setMinEth(uint256 _minEth) public onlyOwner {
        uint256 oldAmount = minEth;
        minEth = _minEth;
        emit LogMinEthChanged(msg.sender, oldAmount, _minEth);
    }

    /**
    * @dev Set the 'charityAddress' to a different contract address
    */
    function setCharityAddress(address _charityAddress) public onlyOwner {
        address oldAddress = charityAddress;
        charityAddress = _charityAddress;
        emit LogCharityAddressChanged(msg.sender, oldAddress, _charityAddress);
    }

    //allow freezing of everything

}