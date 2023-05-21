//SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.17;

interface IERC20 {
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);

    function approve(address, uint256) external;

    function decimals() external view returns (uint256);

    function balanceOf(address to) external view returns (uint256);

    function freeBalanceOf(address account) external view returns (uint256);

    function lockBalanceOf(address account) external view returns (uint256);

    function freeBalanceBySpender(
        address account,
        address spender
    ) external view returns (uint256);

    function lockBalanceBySpender(
        address account,
        address spender
    ) external view returns (uint256);

    function vestingContract() external view returns (address);

    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;
}
