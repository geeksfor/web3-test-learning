// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SimpleERC721 {
    // ============ errors ============
    error ZeroAddress();
    error TokenAlreadyMinted(uint256 tokenId);
    error NonexistentToken(uint256 tokenId);

    // ============ events ============
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId
    );

    // ============ storage ============
    mapping(uint256 => address) private _ownerOf;
    mapping(address => uint256) private _balanceOf;

    // ============ views ============
    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _ownerOf[tokenId];
        if (owner == address(0)) revert NonexistentToken(tokenId);
        return owner;
    }

    function balanceOf(address owner) public view returns (uint256) {
        if (owner == address(0)) revert ZeroAddress();
        return _balanceOf[owner];
    }

    // ============ mint ============
    function mint(address to, uint256 tokenId) external {
        if (to == address(0)) revert ZeroAddress();
        if (_ownerOf[tokenId] != address(0)) revert TokenAlreadyMinted(tokenId);

        _ownerOf[tokenId] = to;
        unchecked {
            _balanceOf[to] += 1;
        }
        emit Transfer(address(0), to, tokenId);
    }
}
