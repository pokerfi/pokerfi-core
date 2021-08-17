// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract Poker is AccessControl, ERC721, ERC721Enumerable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    string private _baseTokenURI;

    uint256 private _tokenIdTracker;

    struct Card {
        uint8 rank;
        uint8 suit;
        uint8 level;

        uint32 hashRate;
    }

    mapping(uint256 => Card) private _cards;

    event BaseURIUpdated(string previousBaseURI, string newBaseURI);

    event Created(uint256 indexed tokenId, address indexed to, uint8 rank, uint8 suit, uint8 level);
    event Removed(uint256 indexed tokenId, address indexed from);

    constructor() ERC721("Poker", "POKER") {
        _setRoleAdmin(MINTER_ROLE, DEFAULT_ADMIN_ROLE);

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function setBaseURI(string calldata newBaseURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        string memory previousBaseURI = _baseTokenURI;
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(previousBaseURI, newBaseURI);
    }

    function baseURI() public view returns (string memory) {
        return _baseURI();
    }

    function exists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    function allTokens(uint256 startIndex, uint256 endIndex) public view returns (uint256[] memory) {
        require(startIndex < endIndex && endIndex <= totalSupply(), "Invalid index");

        uint256[] memory result = new uint256[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = tokenByIndex(i);
        }

        return result;
    }

    function ownedTokens(address account, uint256 startIndex, uint256 endIndex ) public view returns (uint256[] memory) {
        require(startIndex < endIndex && endIndex <= balanceOf(account), "Invalid index");

        uint256[] memory result = new uint256[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = tokenOfOwnerByIndex(account, i);
        }

        return result;
    }

    function cards(uint256 tokenId) public view returns (uint8 rank, uint8 suit, uint8 level, uint32 hashRate) {
        Card memory card = _cards[tokenId];
        return (uint8(card.rank), uint8(card.suit), card.level, card.hashRate);
    }

    function create(address to, uint8 rank, uint8 suit, uint8 level, uint32 hashRate) external onlyRole(MINTER_ROLE) returns (uint256 tokenId) {
        require(level <= 9 && rank <= 13 && suit <= 3, "Invalid parameters");

        _tokenIdTracker += 1;
        tokenId = (10000 * _tokenIdTracker) + (1000 * level) + (10 * rank) + suit;

        Card storage card = _cards[tokenId];
        card.rank = rank;
        card.suit = suit;
        card.level = level;
        card.hashRate = hashRate;

        _safeMint(to, tokenId);

        emit Created(tokenId, to, rank, suit, level);
    }

    function remove(uint256 tokenId) external {
        address from = _msgSender();
        require(_isApprovedOrOwner(from, tokenId), "Caller is not owner nor approved");

        _burn(tokenId);

        emit Removed(tokenId, from);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }
}
