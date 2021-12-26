// SPDX-License-Identifier: MIT

pragma solidity ^0.8.5;

import "./libs/SafeMath.sol";
import "./libs/Address.sol";
import "./libs/Ownable.sol";
import "./libs/IERC20.sol";
import "./libs/IUniswapV2Router02.sol";
import "./libs/IUniswapV2Factory.sol";
import "./libs/IUniswapV2Pair.sol";

contract BitBoy is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    address public constant DEAD_ADDRESS =
        0x000000000000000000000000000000000000dEaD;
    uint256 public constant MAX_TAX_FEE = 2000; // Max tax fee - 20%
    uint256 public constant MAX_BURN_FEE = 1000; // Max burn fee - 10%

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) private _isExcludedFromFee;

    mapping(address => bool) private _isExcludedFromAntiWhale;

    mapping(address => bool) private _isExcluded;
    address[] private _excluded;

    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal;
    uint256 private _rTotal;
    uint256 private _tFeeTotal;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    uint256 public _taxFee;
    uint256 private _previousTaxFee;

    uint256 private _burnFee;
    uint256 private _previousBurnFee;

    uint256 public _maxTxAmount;
    uint256 private _previousMaxTxAmount;

    uint256 public _maxHoldAmount;
    uint256 private _previousMaxHoldAmount;

    event MaxTxAmountUpdated(
        address ownerAddress,
        uint256 oldValue,
        uint256 newValue
    );
    event MaxHoldAmountUpdated(
        address ownerAddress,
        uint256 oldValue,
        uint256 newValue
    );
    event TaxFeeUpdated(
        address ownerAddress,
        uint256 oldValue,
        uint256 newValue
    );
    event BurnFeeUpdated(
        address ownerAddress,
        uint256 oldValue,
        uint256 newValue
    );
    event ExcludedFromFee(address ownerAddress, address accountAddress);
    event IncludedInFee(address ownerAddress, address accountAddress);
    event ExcludedFromReward(address ownerAddress, address accountAddress);
    event IncludedInReward(address ownerAddress, address accountAddress);
    event ExcludedFromAntiWhale(address ownerAddress, address accountAddress);
    event IncludedInAntiWhale(address ownerAddress, address accountAddress);

    constructor() {
        _name = "BitBoy Crypto";
        _symbol = "BITBOY";
        _decimals = 18;
        _tTotal = 1000000000000000 * 10**_decimals;
        _rTotal = (MAX - (MAX % _tTotal));

        _taxFee = 500;
        _previousTaxFee = _taxFee;
        _burnFee = 500;
        _previousBurnFee = _burnFee;
        _maxTxAmount = _tTotal.div(10000); // max transaction amount - 1%
        _previousMaxTxAmount = _maxTxAmount;
        _maxHoldAmount = _tTotal.div(10000).mul(2); // max hold amount - 2%
        _previousMaxHoldAmount = _maxHoldAmount;

        _rOwned[owner()] = _rTotal;

        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[DEAD_ADDRESS] = true;
        _isExcludedFromFee[address(this)] = true;

        _isExcludedFromAntiWhale[owner()] = true;
        _isExcludedFromAntiWhale[DEAD_ADDRESS] = true;

        _isExcluded[DEAD_ADDRESS] = true;
        _excluded.push(DEAD_ADDRESS);

        emit Transfer(address(0), owner(), _tTotal);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function deliver(uint256 tAmount) public {
        address sender = _msgSender();
        require(
            !_isExcluded[sender],
            "Excluded addresses cannot call this function"
        );
        (uint256 rAmount, , , , , ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee)
        public
        view
        returns (uint256)
    {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount, , , , , ) = _getValues(tAmount);
            return rAmount;
        } else {
            (, uint256 rTransferAmount, , , , ) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount)
        public
        view
        returns (uint256)
    {
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        if (from != owner() && to != owner()) {
            require(
                amount <= _maxTxAmount,
                "Transfer amount exceeds the maxTxAmount."
            );
        }

        bool takeFee = true;

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            takeFee = false;
        }

        _tokenTransfer(from, to, amount, takeFee);
    }

    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee
    ) private {
        if (!takeFee) removeAllFee();

        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }

        if (!takeFee) restoreAllFee();
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tBurn
        ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _burnTokens(tBurn);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tBurn
        ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _burnTokens(tBurn);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tBurn
        ) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _burnTokens(tBurn);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferBothExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tBurn
        ) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _burnTokens(tBurn);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getValues(uint256 tAmount)
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        (uint256 tTransferAmount, uint256 tFee, uint256 tBurn) = _getTValues(
            tAmount
        );
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
            tAmount,
            tFee,
            tBurn,
            _getRate()
        );
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tBurn);
    }

    function _getTValues(uint256 tAmount)
        private
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 tFee = calculateTaxFee(tAmount);
        uint256 tBurn = calculateBurnFee(tAmount);
        uint256 tTransferAmount = tAmount.sub(tFee).sub(tBurn);
        return (tTransferAmount, tFee, tBurn);
    }

    function _getRValues(
        uint256 tAmount,
        uint256 tFee,
        uint256 tBurn,
        uint256 currentRate
    )
        private
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rBurn = tBurn.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rBurn);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (
                _rOwned[_excluded[i]] > rSupply ||
                _tOwned[_excluded[i]] > tSupply
            ) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function _burnTokens(uint256 tBurn) private {
        uint256 currentRate = _getRate();
        uint256 rBurn = tBurn.mul(currentRate);
        _rOwned[DEAD_ADDRESS] = _rOwned[DEAD_ADDRESS].add(rBurn);
        _tOwned[DEAD_ADDRESS] = _tOwned[DEAD_ADDRESS].add(tBurn);
    }

    function calculateTaxFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_taxFee).div(10**3);
    }

    function calculateBurnFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_burnFee).div(10**4);
    }

    function removeAllFee() private {
        if (_taxFee == 0 && _burnFee == 0) return;

        _previousTaxFee = _taxFee;
        _previousBurnFee = _burnFee;

        _taxFee = 0;
        _burnFee = 0;
    }

    function restoreAllFee() private {
        _taxFee = _previousTaxFee;
        _burnFee = _previousBurnFee;
    }

    function isExcludedFromAntiWhale(address account)
        public
        view
        returns (bool)
    {
        return _isExcludedFromAntiWhale[account];
    }

    function excludeFromAntiWhale(address account) public onlyOwner {
        require(
            !_isExcludedFromAntiWhale[account],
            "BITBOY: account already excluded"
        );
        _isExcludedFromAntiWhale[account] = true;
        emit ExcludedFromAntiWhale(owner(), account);
    }

    function includeInAntiWhale(address account) external onlyOwner {
        require(
            _isExcludedFromAntiWhale[account],
            "BITBOY: account already excluded"
        );
        _isExcludedFromAntiWhale[account] = false;
        emit IncludedInAntiWhale(owner(), account);
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function excludeFromReward(address account) public onlyOwner {
        require(!_isExcluded[account], "BITBOY: account already excluded");
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
        emit ExcludedFromReward(owner(), account);
    }

    function includeInReward(address account) external onlyOwner {
        require(_isExcluded[account], "BITBOY: account already excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
        emit IncludedInReward(owner(), account);
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function excludeFromFee(address account) public onlyOwner {
        require(
            !_isExcludedFromFee[account],
            "BITBOY: account already excluded"
        );
        _isExcludedFromFee[account] = true;
        emit ExcludedFromFee(owner(), account);
    }

    function includeInFee(address account) public onlyOwner {
        require(
            _isExcludedFromFee[account],
            "BITBOY: account already included"
        );
        _isExcludedFromFee[account] = false;
        emit IncludedInFee(owner(), account);
    }

    function setTaxFee(uint256 taxFee) external onlyOwner {
        require(taxFee <= MAX_TAX_FEE, "BITBOY: taxFee exceeds the limitation");
        require(_taxFee != taxFee, "BITBOY: same value already set");
        emit TaxFeeUpdated(owner(), _taxFee, taxFee);
        _taxFee = taxFee;
    }

    function setBurnFee(uint256 burnFee) external onlyOwner {
        require(
            burnFee <= MAX_BURN_FEE,
            "BITBOY: burnFee exceeds the limitation"
        );
        require(_burnFee != burnFee, "BITBOY: same value already set");
        emit BurnFeeUpdated(owner(), _burnFee, burnFee);
        _burnFee = burnFee;
    }

    function setMaxTxAmount(uint256 maxTxAmount) external onlyOwner {
        require(maxTxAmount > 0, "BITBOY: all transfer will be failed");
        require(_maxTxAmount != maxTxAmount, "BITBOY: same value already set");
        emit MaxTxAmountUpdated(owner(), _maxTxAmount, maxTxAmount);
        _maxTxAmount = maxTxAmount;
    }

    function setMaxHoldAmount(uint256 maxHoldAmount) external onlyOwner {
        require(maxHoldAmount > 0, "BITBOY: no account can hold token");
        require(
            _maxHoldAmount != maxHoldAmount,
            "BITBOY: same value already set"
        );
        emit MaxHoldAmountUpdated(owner(), _maxHoldAmount, maxHoldAmount);
        _maxHoldAmount = maxHoldAmount;
    }

    function presale(bool _presale) external onlyOwner {
        if (_presale) {
            removeAllFee();
            _previousMaxTxAmount = _maxTxAmount;
            _maxTxAmount = totalSupply();
            _previousMaxHoldAmount = _maxHoldAmount;
            _maxHoldAmount = totalSupply();
        } else {
            restoreAllFee();
            _maxTxAmount = _previousMaxTxAmount;
            _maxHoldAmount = _previousMaxHoldAmount;
        }
    }
}
