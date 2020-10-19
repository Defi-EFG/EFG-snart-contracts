pragma solidity 0.4.26;

import "./ECRC20/EFGToken.sol";
import "./ECRC20/GPTToken.sol";

contract StakingContract {
    address owner;
    uint256 mintingRate;
    GPTToken GPT;
    EFGToken EFG;

    constructor (address _EFG_addr,address  _GPT_addr) {
        mintingRate = 1286; /* mining rate per second in e-16 */
        GPT = GPTToken(_GPT_addr); /* smart contract address of GPT , 4 decimal places */
        EFG = EFGToken(_EFG_addr); /* smart contract address of EFG , 8 decimal places*/
    }

    struct Minting {
        uint256 lockedAmount; /* EFG, 8 decimales*/
        uint256 lastClaimed ; /* timestamp */
        uint256 unclaimedAmount; /* 16 decimals */
    }
    mapping(address => Minting) private locked;

    event ClaimStakedGPT(bool result, address beneficiar, uint GPTAmount);
    event MintGPTEvent(bool result, address beneficiar, uint EFGAmount);
    event WithdrawEFGEvent(bool result, address beneficiar, uint EFGAmount);
    
    /*
     * @notice users can deposit EFG for staking
     * @param _amount - deposit amount of EFG , 8 decimals
     * @return bool - true on success , else false
     */
    function mintGPT(uint256 _amount) external returns(bool) {
        require(_amount > 0);
        /* check if contract still has GPT */
        if (unclaimedGPT() == 0) {
            emit MintGPTEvent(false, msg.sender, _amount);
            return false;
        }
        /* transfer EFG to this contract - it will fail if not appoved before */
        bool result = EFG.transferFrom(msg.sender, address(this), _amount);
        if (!result) {
            emit MintGPTEvent(false, msg.sender, _amount);
            return false;
        }

        /* create or update the minting info */
        Minting storage m = locked[msg.sender];

        if(m.lockedAmount > 0) {
            /* this is a topup*/
            updateUnclaimedAmount(msg.sender);
        }
        m.lockedAmount += _amount;
        m.lastClaimed = block.timestamp;

        emit MintGPTEvent(true , msg.sender, _amount);
        return true;
    }

    /*
     * @notice claim any unclaimed GPT (withdraw)
     * @param _beneficiar - destination address
     * @return bool - true on success
     */
    function claimStakedGPT(address _beneficiar) external returns(bool) {
        /* first check if the contract has any GPT left*/
        require (unclaimedGPT() > 0);
        /* check if there was at least one EFG deposit*/
        Minting storage m = locked[msg.sender];
        if (m.lastClaimed == 0) { /* zero timestamp */
            emit ClaimStakedGPT(false, msg.sender, 0);
            return false;
        }

        updateUnclaimedAmount(msg.sender);
        m.lastClaimed = block.timestamp;
        uint256 allowedGPT = m.unclaimedAmount;
        if (allowedGPT > unclaimedGPT()) {
            allowedGPT = unclaimedGPT();
        }

        /* send out the GPT */
        bool result = GPT.transfer(_beneficiar, allowedGPT);
        if (!result) {
            emit ClaimStakedGPT(false, _beneficiar, allowedGPT);
            return false;
        }

        m.unclaimedAmount -= allowedGPT;
        emit ClaimStakedGPT(true, _beneficiar, allowedGPT);
        return true;
    }

    /*
     * @notice withdraw EFG , beneficiar can withdraw to any address
     * @param _beneficiar - destination address
     * @param _amount - amount of EFG to withdrawn
     * @return bool - true on success
     */
    function withdrawEFG(address _beneficiar, uint256 _amount) external returns (bool){
        Minting storage m = locked[msg.sender];
        require(_amount <= m.lockedAmount);
        
        /* send the tokens */
        bool result = EFG.transfer(_beneficiar, _amount);
        if(!result) {
            emit WithdrawEFGEvent(false, msg.sender, _amount);
            return false;
        }
        
        updateUnclaimedAmount(msg.sender);
        m.lockedAmount -= _amount;
        m.lastClaimed = block.timestamp;
        emit WithdrawEFGEvent(true, _beneficiar, _amount);
        
        return true;
    }

    /*
     * @notice returns mining info for the beneficiar
     * @param _beneficiar
     * @return (uint256, uint256, uint256) - returns locked EFG, last topup timestamp and unclaimed amount
     */
    function mintingInfo(address _beneficiar) external view returns (uint256, uint256, uint256) {
        Minting memory m = locked[_beneficiar];
        return (m.lockedAmount, m.lastClaimed, m.unclaimedAmount);
    }

    /*
     * @notice return remaing GPT of smart contract , 4 decimal places
     * @return uint256 - the amount of remaining tokens
     */
    function unclaimedGPT() public view returns (uint256){
        return GPT.balanceOf(address(this));
    }

    /*
     * @notice updates the total staked GPT amount in a minting contract
     * @param _minters_addr
     */
    function updateUnclaimedAmount(address _minters_addr) internal {
        Minting storage m = locked[msg.sender];
        m.unclaimedAmount += computeUnclaimedAmount((block.timestamp - m.lastClaimed), mintingRate, m.lockedAmount);
        return ;
    }

    /*
     * @notice for computing the staked amount of last period only (pure function)
     * @param _period
     * @param _rate
     * @param _staked
     * return uint256 - the amount of unclaimed GPT
     */

    function computeUnclaimedAmount(uint _period, uint _rate, uint _staked) internal pure returns(uint256) {
        uint256 stakedAmount;
        
        stakedAmount = _period * _rate * _staked;
        stakedAmount /= 1e16; /* staking rate is in e-16 */
        
        return stakedAmount;
    }
}