// SPDX-License-Identifier: MIT

pragma solidity >=0.8.13 <0.9.0;


import "./erc721a/contracts/extensions/ERC721AQueryable.sol";
import "./erc721a/contracts/extensions/ERC4907A.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DefaultOperatorFilterer} from "./operator-filter-registry/src/DefaultOperatorFilterer.sol";

contract TenKa is
    ERC721AQueryable,
    ERC4907A,
    ERC2981,
    Ownable,
    ReentrancyGuard,
    DefaultOperatorFilterer
{
    using Strings for uint256;
    address private _royaltyReceiver;
    uint256 private _royaltyPercentage;
    bytes32 public merkleRoot;
    bytes32 public fcfsMerkleRoot;
    mapping(address => bool) public fcfsClaimed;
    mapping(address => bool) public publicClaimed;
    mapping(address => uint256) public amountMinted;

    string public uriPrefix = "";
    string public hiddenMetadataUri;

    uint256 public cost = 1 ether;
    uint256 public maxSupply = 5000;
    uint256 public whitelistMaxSupply = 5000;
    uint256 public whiteFcfsMaxSupply = 5000;
    uint256 public maxMintAmountPerTx = 5;
    uint256 public maxAmountPerWallet = 5;

    uint256 public totalWhitelistMinted = 0;
    uint256 public totalFcfsMinted = 0;

    bool public whitelistMintEnabled = false;
    bool public fcfsMintEnabled = false;
    bool public publicMintEnabled = false;
    bool public revealed = false;

    constructor() ERC721A("10ka", "10KA") Ownable(msg.sender) {
        _royaltyReceiver = msg.sender;
        _royaltyPercentage = 5;
    }

    modifier mintCompliance(uint256 _mintAmount) {
        require(
            _mintAmount > 0 && _mintAmount <= maxMintAmountPerTx,
            "Invalid mint amount!"
        );
        require(
            totalSupply() + _mintAmount <= maxSupply,
            "Max supply exceeded!"
        );
        require(
            amountMinted[msg.sender] + _mintAmount <= maxAmountPerWallet,
            "Max amount per wallet exceeded!"
        );
        _;
    }

    modifier mintPriceCompliance(uint256 _mintAmount) {
        require(msg.value == cost * _mintAmount, "Insufficient funds!");
        _;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721A, ERC4907A, ERC2981, IERC721A) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function whitelistMint(
        uint256 _mintAmount,
        bytes32[] calldata _merkleProof
    ) public payable mintCompliance(_mintAmount) mintPriceCompliance(_mintAmount) {
        require(whitelistMintEnabled, "The whitelist sale is not enabled!");
        require(
            totalWhitelistMinted + _mintAmount <= whitelistMaxSupply,
            "Whitelist max supply reached!"
        );
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(
            MerkleProof.verify(_merkleProof, merkleRoot, leaf),
            "Invalid proof!"
        );

        totalWhitelistMinted += _mintAmount;
        amountMinted[msg.sender] += _mintAmount;
        _safeMint(msg.sender, _mintAmount);
    }

    function fcfsMint(
        uint256 _mintAmount,
        bytes32[] calldata _merkleProof
    ) public payable mintCompliance(_mintAmount) mintPriceCompliance(_mintAmount) {
        require(fcfsMintEnabled, "The FCFS sale is not enabled!");
        require(
            totalFcfsMinted + _mintAmount <= whiteFcfsMaxSupply,
            "FCFS max supply reached!"
        );
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(
            MerkleProof.verify(_merkleProof, fcfsMerkleRoot, leaf),
            "Invalid proof!"
        );

        totalFcfsMinted += _mintAmount;
        amountMinted[msg.sender] += _mintAmount;
        _safeMint(msg.sender, _mintAmount);
    }


    function mint(
        uint256 _mintAmount
    ) public payable mintCompliance(_mintAmount) mintPriceCompliance(_mintAmount) {
        require(publicMintEnabled, "The public sale is not enabled!");
        _safeMint(msg.sender, _mintAmount);
    }

    function airdrop(uint256 _mintAmount, address _receiver) public onlyOwner {
        require(
            totalSupply() + _mintAmount <= maxSupply,
            "Max supply exceeded!"
        );
        _safeMint(_receiver, _mintAmount);
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 0;
    }

    function feeDenominator() external virtual returns (uint96) {
        return _feeDenominator();
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function deleteDefaultRoyalty() external onlyOwner {
        _deleteDefaultRoyalty();
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) external onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    function resetTokenRoyalty(uint256 tokenId) external onlyOwner {
        _resetTokenRoyalty(tokenId);
    }

    function _baseURI()
        internal
        view
        virtual
        override(ERC721A)
        returns (string memory)
    {
        return uriPrefix;
    }

    function tokenURI(
        uint256 _tokenId
    ) public view virtual override(ERC721A, IERC721A) returns (string memory) {
        require(
            _exists(_tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        if (revealed == false) {
            return hiddenMetadataUri;
        }

        string memory currentBaseURI = _baseURI();
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        _tokenId.toString()
                    )
                )
                : "";
    }

    function setRevealed(bool _state) public onlyOwner {
        revealed = _state;
    }

    function setCost(uint256 _cost) public onlyOwner {
        cost = _cost;
    }

    function setMaxMintAmountPerTx(
        uint256 _maxMintAmountPerTx
    ) public onlyOwner {
        maxMintAmountPerTx = _maxMintAmountPerTx;
    }

    function setHiddenMetadataUri(
        string memory _hiddenMetadataUri
    ) public onlyOwner {
        hiddenMetadataUri = _hiddenMetadataUri;
    }

    function setUriPrefix(string memory _uriPrefix) public onlyOwner {
        uriPrefix = _uriPrefix;
    }

    function setMerkleRoot(bytes32 _merkleRoot) public onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setFcfsMerkleRoot(bytes32 _fcfsMerkleRoot) public onlyOwner {
        fcfsMerkleRoot = _fcfsMerkleRoot;
    }

    function setWhitelistMintEnabled(bool _state) public onlyOwner {
        whitelistMintEnabled = _state;
    }

    function setFcfsMintEnabled(bool _state) public onlyOwner {
        fcfsMintEnabled = _state;
    }

    function setPublicMintEnabled(bool _state) public onlyOwner {
        publicMintEnabled = _state;
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) public override(ERC721A, IERC721A) onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(
        address operator,
        uint256 tokenId
    )
        public
        payable
        override(ERC721A, IERC721A)
        onlyAllowedOperatorApproval(operator)
    {
        super.approve(operator, tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override(ERC721A, IERC721A) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override(ERC721A, IERC721A) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public payable override(ERC721A, IERC721A) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function withdraw() public onlyOwner nonReentrant {
        (bool wf, ) = payable(owner()).call{value: address(this).balance}("");
        require(wf);
    }
}
