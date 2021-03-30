// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;

import "./Attribute.sol";
import "./BitiToken.sol";
import "./library/ERC721.sol";
import "./library/IBitiToken.sol";
import "./library/utils/SafeMath.sol";
import "./library/utils/Math.sol";
import "./library/extensions/ReentrancyGuard.sol";

interface IMarketplace {
  function hasOrder(address nftAddress, uint256 assetId) external returns (bool);
  function cancelOrder(address nftAddress, uint256 assetId) external;
}

contract BitiBots is ERC721, Attribute, ReentrancyGuard {
    using SafeMath for uint;

    enum Functions { HASH_FACTOR }
    uint private currentTokenId;

    uint public constant _TIMELOCK = 1 days;
    uint public constant decayPeriod = 201600; // How many blocks before rewards are reduced, 1 WEEK in blocks
    uint public constant decays = 12; // Number of decay periods
    uint public immutable startBlock; // when bitibots comes alive.
    uint public constant minCreatedDurationBeforeBreed = 3 days; // Minimum duration since bitibots is created before it can be bred.
    uint public constant baseBreedingCost = 1 ether;
    uint public constant buyGen0Cost = 1 ether;
    uint public constant maxGen0Count = 10000;

    uint public timelockValue; // value that sethashFactor will lookup to
    uint public hashFactor = 0.1 ether;
    uint public gen0Count;

    address payable private owner;
    address public feeCollector;

    mapping(Functions => uint256) public timelock;

    IBitiToken public biti;

    struct BitiBotBio {
        uint id;
        uint dna;
        uint generation;
        uint hashRate; // 4 - 8
        uint lastMine;
        uint createdAt;
    }

    mapping(uint => BitiBotBio) public bitiBotsData;

    IMarketplace public marketplace;
    bool public marketplaceSet = false;

    // events
    event Minted(address to, uint id, uint dna, uint generation, uint hashRate, uint lastMine, uint createdAt);
    event Breed(uint firstParent, uint secondParent, uint child);
    event Mined(uint botId, uint lastMine);

    constructor(IBitiToken _biti, uint _startBlock, address _feeCollector) ERC721("BitiBot", "BITIB") {
        owner = msg.sender;
        feeCollector = _feeCollector;
        _setBaseURI("https://api.biti.city/metadata/");
        biti = _biti;
        startBlock = _startBlock;
    }

    /**
     * @dev Sets the marketplace contract (only once)
     */
    function setMarketplace(address _marketplace) public onlyOwner {
        require(!marketplaceSet, "Marketplace has already been set");
        marketplace = IMarketplace(_marketplace);
        marketplaceSet = true;
    }


    // ---- Start of Mining Decay Logic  ---

    /**
     * @notice Returns the phase at block number
     */
    function phase(uint blockNumber) public view returns (uint) {
        if (decayPeriod == 0) {
            return 0;
        }
        if (blockNumber > startBlock) {
            return (blockNumber.sub(startBlock).sub(1)).div(decayPeriod);
        }
        return 0;
    }

    /**
     * @dev Returns the phase at the current block number
     */
    function phase() public view returns (uint) {
        return phase(block.number);
    }

    /**
     * @dev effective hash factor after prorating the hash factor by amount of blocks passed
     */
    function effectiveHashFactor(uint blockNumber) public view returns (uint) {
        uint _phase = phase(blockNumber);
        if (_phase >= decays) {
            return 0;
        }
        return hashFactor.sub(_phase.mul(hashFactor.div(decays)));
    }

    /**
     * @dev current effective hash factor
     */
    function effectiveHashFactor() public view returns (uint) {
        return effectiveHashFactor(block.number);
    }

    /**
     * @dev Timelocked function that sets the base hash factor
     */
    function setHashFactor() onlyOwner notLocked(Functions.HASH_FACTOR) public {
        hashFactor = timelockValue;
    }

    /**
     * @dev Unlocks the ability to set the timelockValue to sethashFactor after _TIMELOCK amount of days
     */
    function unlockSetHashFactor(Functions _fn, uint _value) public onlyOwner {
        timelock[_fn] = block.timestamp + _TIMELOCK;
        timelockValue = _value;
    }

    /**
     * @dev resets and locks the time lock again
     */
    function lockSetHashFactor(Functions _fn) public onlyOwner {
        timelock[_fn] = 0;
    }

    // ---- End of Mining Decay Logic  ---

    // ---- Start of Mining Rewards Logic  ---


    /**
     * @dev Mines the bot
     * @notice All pending rewards are subjected to decay, so mine your bots before the timer!
     */
    function mine(uint tokenId) public nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "owner must be sender");
        _mine(tokenId);
    }


    /**
     * @dev private function that is called by mine and before transfer
     * @notice All pending rewards are subjected to decay, so mine your bots before the timer!
     */
    function _mine(uint tokenId) private {
        BitiBotBio storage bitiBot = bitiBotsData[tokenId];

        uint bitiAmount = mineableAmount(tokenId);
        require(bitiAmount > 0, "bitiAmount must be > 0");
        biti.mint(msg.sender, bitiAmount);
        bitiBot.lastMine = block.timestamp;
        emit Mined(tokenId, bitiBot.lastMine);
    }

    /**
     * @dev helper function that mines all bots of the sender
     * @notice All pending rewards are subjected to decay, so mine your bots before the timer!
     */
    function mineAll() public nonReentrant {
        uint numberOfTokens = balanceOf(msg.sender);
        require(numberOfTokens > 0);
        uint sum = 0;
        for (uint i = 0; i < numberOfTokens; i++) {
            BitiBotBio storage bitiBot = bitiBotsData[tokenOfOwnerByIndex(msg.sender, i)];
            sum = sum.add(mineableAmount(bitiBot.id));
            bitiBot.lastMine = block.timestamp;
            emit Mined(bitiBot.id, bitiBot.lastMine);
        }
        biti.mint(msg.sender, sum);
    }

    /**
     * @dev calculates the mineable amount using a 12 period with (hashRate * effectiveHashRate)
     */
    function mineableAmount(uint tokenId) public view returns (uint) {
        BitiBotBio storage bitiBot = bitiBotsData[tokenId];
        uint timeSinceLastMine = block.timestamp.sub(bitiBot.lastMine);
        return (bitiBot.hashRate.mul(effectiveHashFactor()).mul(timeSinceLastMine)).div(12 weeks);
    }
    // ---- End of Mining Rewards Logic  ---

    /**
    * @dev Mints a token to an address with a tokenURI.
    * @param _to address of the future owner of the token
    */
    function mintTo(address _to, uint dna, uint generation, uint hashRate) private hasStarted returns (uint) {
        uint newTokenId = _getNextTokenId();
        _mint(_to, newTokenId);
        _incrementTokenId();
        BitiBotBio memory bitiBotBio = BitiBotBio(newTokenId, dna, generation, hashRate, block.timestamp, block.timestamp);
        bitiBotsData[newTokenId] = bitiBotBio;
        emit Minted(_to, bitiBotBio.id, bitiBotBio.dna, bitiBotBio.generation, bitiBotBio.hashRate, bitiBotBio.lastMine, bitiBotBio.createdAt);
        return newTokenId;
    }

    /**
     * @dev constructs new gen0 bitibots
     * @param n number of gen 0 bitibots to construct
     */
    function buyGen0(uint n) public payable nonReentrant returns (uint[] memory) {
        uint cost = buyGen0Cost.mul(n);
        require(msg.value >= cost, "not enough bnb");
        require(gen0Count.add(n) <= maxGen0Count, "gen0 has reached maximum count");
        (bool success, ) = feeCollector.call{value: msg.value}("");
        require(success, "transfer to feeCollector failed");

        uint[] memory newTokenIds = new uint[](n);
        for (uint i = 0; i < n; i++) {
            uint dna = randomAllAttributes();
            newTokenIds[i] = mintTo(msg.sender, dna, 0, getHashRateFromDNA(dna, 0));
        }
        gen0Count = gen0Count.add(n);

        return newTokenIds;
    }

    /**
     * @dev construct a offspring and burn sire and matyr
     * @param _first sire (dad)
     * @param _second mare (mom)
     */
    function breed(uint _first, uint _second) public nonReentrant returns (uint) {
        require(ownerOf(_first) == msg.sender && ownerOf(_second) == msg.sender, "must be owner of _first and _second");
        BitiBotBio storage bitiBot1 = bitiBotsData[_first];
        BitiBotBio storage bitiBot2 = bitiBotsData[_second];
        require(block.timestamp >= bitiBot1.createdAt.add(minCreatedDurationBeforeBreed) && block.timestamp >= bitiBot2.createdAt.add(minCreatedDurationBeforeBreed), "min 1 day since inception");

        uint minParentsGeneration = Math.min(bitiBot1.generation, bitiBot2.generation);
        uint offspringGeneration = minParentsGeneration.add(1);
        uint cost = offspringGeneration.mul(baseBreedingCost);
        require(offspringGeneration <= 9, "max gen is gen 9");

        require(biti.balanceOf(msg.sender) >= cost, "not enough balance for cost");
        require(biti.allowance(msg.sender, address(this)) >= cost, "not enough allowance for cost");

        biti.transferFrom(msg.sender, feeCollector, cost);
        _burn(_first);
        _burn(_second);

        uint newDNA = mixAttributes(bitiBot1.dna, bitiBot2.dna);

        uint hashRate = 0;
        if (bitiBot1.generation == minParentsGeneration) { // prevent using OP high gen parents
            hashRate = hashRate.add(bitiBot1.hashRate);
        }

        if (bitiBot2.generation == minParentsGeneration) { // prevent using OP high gen parents
            hashRate = hashRate.add(bitiBot2.hashRate);
        }

        uint newTokenId = mintTo(
            msg.sender,
            newDNA, offspringGeneration,
            hashRate.mul(6).div(10).add(getHashRateFromDNA(newDNA, offspringGeneration)) // 2 parents * 0.6 + offspring 3 ** (gen-1)
        );
        emit Breed(_first, _second, newTokenId);
        return newTokenId;
    }

    /**
     * @dev calculate bitibot's hashrate from it's dna
     * @param dna dna of bitibot
     * @param generation generation number
     */
    function getHashRateFromDNA(uint dna, uint generation) private pure returns (uint) {
        // 0 - eye
        // 1 - body
        // 2 - head
        // 3 - mouth
        // 4 - mental
        if (generation == 0) return 0;
        uint eyeHashRate = 0;
        uint eyeAttribute = getAttribute(dna, 0);
        if (eyeAttribute == 0 || eyeAttribute == 1 || eyeAttribute == 2) {
            eyeHashRate = 3;
        } else if (eyeAttribute == 3 || eyeAttribute == 4) {
            eyeHashRate = 5;
        }  else if (eyeAttribute == 5) {
            eyeHashRate = 8;
        }
        uint bodyHashRate = getAttribute(dna, 1) > 4 ? 2 : 1;
        uint headHashRate = getAttribute(dna, 2) > 5 ? 2 : 1;
        uint mouthHashRate = getAttribute(dna, 3) > 6 ? 2 : 1;
        uint mentalHashRate = getAttribute(dna, 4) > 7 ? 3: 1;
        uint totalHashScore = eyeHashRate.add(bodyHashRate).add(headHashRate).add(mouthHashRate).add(mentalHashRate);
        uint gen = generation - 1;
        totalHashScore = totalHashScore.mul(3**gen);
        return totalHashScore;
    }

    function _getNextTokenId() private view returns (uint) {
        return currentTokenId.add(1);
    }

    function _incrementTokenId() private {
        currentTokenId = currentTokenId.add(1);
    }

    // // --- Hooks ---
    function _beforeTokenTransfer(address from, address to, uint tokenId) internal override {
        uint bitiAmount = mineableAmount(tokenId);
        if (_exists(tokenId) && bitiAmount > 0) {
            _mine(tokenId);
        }
        if (address(marketplace) != address(0) && marketplace.hasOrder(address(this), tokenId)) {
            marketplace.cancelOrder(address(this), tokenId);
        }
        super._beforeTokenTransfer(from, to, tokenId);
    }

    // --- MODIFIERS ---
    modifier notLocked(Functions _fn) {
     require(timelock[_fn] != 0, "Function has not started timelock");
     require(timelock[_fn] <= block.timestamp, "Function is waiting for timelock");
     _;
   }

    modifier onlyOwner() {
        require(owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    modifier hasStarted() {
        require(block.number > 0 && block.number >= startBlock, "BitiBots: not live yet");
        _;
    }
}
