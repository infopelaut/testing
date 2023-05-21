// SPDX-License-Identifier: MIT

pragma solidity >=0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../token/IERC20.sol";

import "hardhat/console.sol";

contract Swap is Ownable {
    // new role
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    IERC20 public zkETH;
    uint256 public withdraw24hLimit = 10 ** 18; // 1 withdraw per 24hours with maximum amount
    uint256 public liquidLevel = 100 * 10 ** 18; // ETH balance - default 100ETH

    IERC20 public zkUSD;
    IERC20 public USDC;
    uint256 public liquidLevelUSDC; // USDC liquid level, default 100k
    uint256 public withdraw24hLimitUSDC; // 1 withdraw per 24hours with maximum amount

    address public treasuryAddress; // address to receive liquid when liquid level is higher than setup
    uint256 public liquidVolatility = 200; // default 20%: 1000 base, the volatility when need refill/

    bool public isPaused;

    mapping(address => uint256) public lastWithdraw;

    mapping(address => bool) public operators;

    event ETHDeposited(address account, uint256 amount);
    event USDCDeposited(address account, uint256 amount);
    event ETHWithdraw(address account, uint256 amount);
    event USDCWithdraw(address account, uint256 amount);
    event ETHBatchWithdraw(address[] accounts, uint256[] amounts, bool[] fails);
    event USDCBatchWithdraw(
        address[] accounts,
        uint256[] amounts,
        bool[] fails
    );

    event RefillETH(address byUser, uint256 amount);
    event RebalanceETH(address byUser, uint256 amount);
    event RefillUSDC(address byUser, uint256 amount);
    event RebalanceUSDC(address byUser, uint256 amount);

    modifier onlyOperator() {
        require(operators[msg.sender] == true, "Only Operator");
        _;
    }

    modifier onlyActive() {
        require(isPaused == false, "Swap is not available");
        _;
    }

    constructor(address usdcAddress, address zkUSDAddress) {
        require(usdcAddress != address(0));
        USDC = IERC20(usdcAddress);
        zkUSD = IERC20(zkUSDAddress);
        // default
        liquidLevelUSDC = 100_000 * 10 ** USDC.decimals();
        // withdraw24hLimitUSDC = 1000 * 10 ** USDC.decimals();
    }

    //// SETTER
    function setWithdrawLimit(
        uint256 ethValue,
        uint256 usdcValue
    ) external onlyOwner {
        if (ethValue > 0) withdraw24hLimit = ethValue;
        if (usdcValue > 0) withdraw24hLimitUSDC = usdcValue;
    }

    function setLiquidLevel(
        uint256 ethValue,
        uint256 usdcValue
    ) external onlyOwner {
        if (ethValue > 0) liquidLevel = ethValue;
        if (usdcValue > 0) liquidLevelUSDC = usdcValue;
    }

    function setLiquidVolatility(uint256 newValue) external onlyOwner {
        liquidVolatility = newValue;
    }

    function setTreasuryAddress(address newValue) external onlyOwner {
        treasuryAddress = newValue;
    }

    function setOperator(address account, bool isSet) external onlyOwner {
        operators[account] = isSet;
    }

    function setPaused(bool isSet) external onlyOwner {
        isPaused = isSet;
    }

    // Set zk
    function setZkETH(address zkETHAddress) external onlyOwner {
        IERC20 _zkETH = IERC20(zkETHAddress);
        require(zkETHAddress != address(0) && _zkETH.decimals() == 18);
        zkETH = _zkETH;
    }

    function setZkUSD(address zkUSDAddress) external onlyOwner {
        IERC20 _zkUSD = IERC20(zkUSDAddress);
        require(
            zkUSDAddress != address(0) && _zkUSD.decimals() == USDC.decimals()
        );
        zkUSD = _zkUSD;
    }

    //// OPERATOR
    // Check current Balance and refill or takeout
    function refillLiquid() external payable onlyOperator {
        uint256 balance = address(this).balance;
        require(
            balance + (liquidLevel * liquidVolatility) / 1000 <= liquidLevel
        );
        uint256 amount = liquidLevel - balance;

        require(amount == msg.value);

        emit RefillETH(msg.sender, amount);
    }

    function rebalanceLiquid() external payable onlyOperator {
        uint256 balance = address(this).balance;
        require(balance > (liquidLevel * (1000 + liquidVolatility)) / 1000);
        uint256 amount = balance - liquidLevel;
        (bool success, ) = payable(treasuryAddress).call{value: amount}("");
        require(success, "Rebalance ETH Failed");

        emit RebalanceETH(msg.sender, amount);
    }

    // Check current Balance and refill or takeout
    function refillLiquidUSDC() external onlyOperator {
        uint256 balance = USDC.balanceOf(address(this));
        require(
            balance + (liquidLevelUSDC * liquidVolatility) / 1000 <=
                liquidLevelUSDC
        );
        uint256 amount = liquidLevelUSDC - balance;
        // transfer in
        require(
            USDC.transferFrom(msg.sender, address(this), amount),
            "Refill USDC Failed"
        );

        emit RefillUSDC(msg.sender, amount);
    }

    function rebalanceLiquidUSDC() external payable onlyOperator {
        uint256 balance = USDC.balanceOf(address(this));
        require(
            balance >= (liquidLevelUSDC * (1000 + liquidVolatility)) / 1000
        );
        uint256 amount = balance - liquidLevelUSDC;
        require(
            USDC.transfer(treasuryAddress, amount),
            "Rebalance USDC Failed"
        );

        emit RebalanceUSDC(msg.sender, amount);
    }

    //// USER
    // deposit ETH
    function deposit(uint256 amount) external payable onlyActive {
        require(address(zkETH) != address(0), "Unsupported");
        require(amount > 0 && amount == msg.value);
        // mint zkETH to user
        zkETH.mint(msg.sender, amount);
        emit ETHDeposited(msg.sender, amount);
    }

    // deposit USDC
    function depositUSDC(uint256 amount) external onlyActive {
        require(
            address(zkUSD) != address(0) && address(USDC) != address(0),
            "Unsupported"
        );
        // transfer USDC to contract
        require(USDC.transferFrom(msg.sender, address(this), amount));
        // mint zkUSD
        zkUSD.mint(msg.sender, amount);
        emit USDCDeposited(msg.sender, amount);
    }

    // withdraw ETH: burn zkETH to get ETH
    // amount: ETH amount
    function withdrawETH(uint256 amount) external payable onlyActive {
        // check limit
        require(withdraw24hLimit >= amount, "Exceed Withdraw Limit");
        require(
            lastWithdraw[msg.sender] + 23 hours < block.timestamp,
            "One Withdraw in 24 hours"
        );
        // check balance
        require(zkETH.freeBalanceOf(msg.sender) >= amount, "Not Enough zkETH");
        require(address(this).balance >= amount, "Not Enough ETH");
        // burn
        zkETH.burn(msg.sender, amount);
        // send ETH
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdraw Failed");

        // update withdraw time
        lastWithdraw[msg.sender] = block.timestamp;

        emit ETHWithdraw(msg.sender, amount);
    }

    function withdrawUSDC(uint256 amount) external onlyActive {
        // check limit
        require(withdraw24hLimitUSDC >= amount, "Exceed Withdraw Limit");
        require(
            lastWithdraw[msg.sender] + 23 hours < block.timestamp,
            "One Withdraw in 24 hours"
        );
        // check balance
        require(zkUSD.freeBalanceOf(msg.sender) >= amount, "Not Enough zkUSD");
        require(USDC.balanceOf(address(this)) >= amount, "Not Enough USDC");
        // burn
        zkUSD.burn(msg.sender, amount);
        // send USDC
        require(USDC.transfer(msg.sender, amount), "Withdraw Failed");

        // update withdraw time
        lastWithdraw[msg.sender] = block.timestamp;

        emit USDCWithdraw(msg.sender, amount);
    }

    // batch widthdraw by Operator
    function batchWidthdrawETH(
        address[] memory accounts,
        uint256[] memory amounts
    ) external onlyOperator {
        uint256 totalAmount;
        bool[] memory fails = new bool[](accounts.length);
        for (uint256 i; i < accounts.length; i++) {
            // check zkETH balance
            if (zkETH.freeBalanceOf(accounts[i]) < amounts[i]) fails[i] = true;
            else totalAmount += amounts[i];
        }
        // require enough balance
        require(address(this).balance >= totalAmount, "Not Enough ETH");
        require(totalAmount > 0);
        // burn and send
        for (uint256 i; i < accounts.length; i++) {
            if (fails[i] == false) {
                zkETH.burn(accounts[i], amounts[i]);
                (bool success, ) = payable(accounts[i]).call{value: amounts[i]}(
                    ""
                );
                require(success, "Withdraw Failed");
                // update withdraw time
                lastWithdraw[accounts[i]] = block.timestamp;
            }
        }
        emit ETHBatchWithdraw(accounts, amounts, fails);
    }

    // withdraw USDC: burn zkUSD to get USDC
    function batchWidthdrawUSDC(
        address[] memory accounts,
        uint256[] memory amounts
    ) external onlyOperator {
        uint256 totalAmount;
        bool[] memory fails = new bool[](accounts.length);
        for (uint256 i; i < accounts.length; i++) {
            // check zkETH balance
            if (zkUSD.freeBalanceOf(accounts[i]) < amounts[i]) fails[i] = true;
            else totalAmount += amounts[i];
        }
        // require enough balance
        require(
            USDC.balanceOf(address(this)) >= totalAmount,
            "Not Enough USDC"
        );
        require(totalAmount > 0);
        // burn and send
        for (uint256 i; i < accounts.length; i++) {
            if (fails[i] == false) {
                zkUSD.burn(accounts[i], amounts[i]);
                require(
                    USDC.transfer(accounts[i], amounts[i]),
                    "Withdraw Failed"
                );
                // update withdraw time
                lastWithdraw[accounts[i]] = block.timestamp;
            }
        }
        emit USDCBatchWithdraw(accounts, amounts, fails);
    }
}
