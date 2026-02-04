// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

contract SimpleERC721 {
    // ============ errors ============
    error ZeroAddress();
    error TokenAlreadyMinted(uint256 tokenId);
    error NonexistentToken(uint256 tokenId);
    error NotOwnerNorApproved();
    error InvalidFrom();
    error UnsafeRecipient();

    // ============ events ============
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId
    );
    event Approval(
        address indexed owner,
        address indexed approved,
        uint256 indexed tokenId
    );
    event ApprovalForAll(
        address indexed owner,
        address indexed operator,
        bool approved
    );

    // ============ storage ============
    mapping(uint256 => address) private _ownerOf;
    mapping(address => uint256) private _balanceOf;

    mapping(uint256 => address) private _tokenApprovals; // getApproved
    mapping(address => mapping(address => bool)) private _operatorApprovals; // isApprovedForAll

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

    function getApproved(uint256 tokenId) public view returns (address) {
        // 标准里：对不存在 tokenId 通常 revert
        ownerOf(tokenId);
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(
        address owner,
        address operator
    ) public view returns (bool) {
        return _operatorApprovals[owner][operator];
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

    // ============ approvals ============
    function approve(address to, uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        // 只有 owner 或 operator 可以 approve
        if (msg.sender != owner && !_operatorApprovals[owner][msg.sender])
            revert NotOwnerNorApproved();
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    // ============ transfers ============
    function transferFrom(address from, address to, uint256 tokenId) public {
        if (to == address(0)) revert ZeroAddress();
        address owner = ownerOf(tokenId);
        if (owner != from) revert InvalidFrom();
        bool authorized = (msg.sender == owner) ||
            (msg.sender == _tokenApprovals[tokenId]) ||
            (_operatorApprovals[owner][msg.sender]);
        if (!authorized) revert NotOwnerNorApproved();

        // 清单 token 授权（非常关键的测试点）
        if (_tokenApprovals[tokenId] != address(0)) {
            _tokenApprovals[tokenId] = address(0);
            emit Approval(owner, address(0), tokenId);
        }
        unchecked {
            _balanceOf[from] -= 1;
            _balanceOf[to] += 1;
        }
        _ownerOf[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public {
        transferFrom(from, to, tokenId);
        // 如果 to 是合约，必须实现 IERC721Receiver
        if (to.code.length > 0) {
            bytes4 ret = IERC721Receiver(to).onERC721Received(
                msg.sender,
                from,
                tokenId,
                data
            );
            if (ret != IERC721Receiver.onERC721Received.selector)
                revert UnsafeRecipient();
        }
    }
}
