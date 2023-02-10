// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../libraries/uniswap/FixedPoint.sol";

import "../Permissions.sol";

/// @title Moving Average
/// @author 0xScotch <scotch@malt.money>
/// @notice For tracking the average of a data stream over time
/// @dev Based on the cumulativeValue mechanism for TWAP in uniswapV2
contract MovingAverage is Permissions {
  using FixedPoint for *;

  struct Sample {
    uint64 timestamp;
    uint256 value;
    uint256 cumulativeValue;
    uint256 lastValue;
  }

  bytes32 public immutable UPDATER_ROLE;

  uint256 public sampleLength;
  uint256 public cumulativeValue;
  uint256 public sampleMemory;
  uint256 public defaultValue;

  uint64 public blockTimestampLast;

  uint256 private counter;
  uint256 public activeSamples;

  Sample[] private samples;

  event Update(uint256 value, uint256 cumulativeValue);

  constructor(
    address _repository,
    address initialAdmin,
    uint256 _sampleLength, // eg 5min represented as seconds
    uint256 _sampleMemory,
    uint256 _defaultValue,
    address _updater
  ) {
    require(_repository != address(0), "MA: Repository addr(0)");
    require(initialAdmin != address(0), "MA: Admin addr(0)");
    require(_sampleMemory > 1, "MA: SampleMemory > 1");

    _initialSetup(_repository);
    UPDATER_ROLE = 0x73e573f9566d61418a34d5de3ff49360f9c51fec37f7486551670290f6285dab;
    _roleSetup(
      0x73e573f9566d61418a34d5de3ff49360f9c51fec37f7486551670290f6285dab,
      initialAdmin
    );
    _roleSetup(
      0x73e573f9566d61418a34d5de3ff49360f9c51fec37f7486551670290f6285dab,
      _updater
    );

    sampleLength = _sampleLength;
    sampleMemory = _sampleMemory;
    defaultValue = _defaultValue;

    for (uint256 i = 0; i < _sampleMemory; i++) {
      samples.push();
    }
  }

  /*
   * PUBLIC VIEW METHODS
   */
  function getValue() public view returns (uint256) {
    if (activeSamples < 2) {
      return defaultValue;
    } else if (activeSamples == 2) {
      Sample storage _currentSample = _getCurrentSample();
      return _currentSample.value;
    } else if (activeSamples < sampleMemory) {
      // Subtract 2 because this is a lookback from the current sample.
      // activeSamples - 1 is the in progress sample. - 2 is the active sample
      // IE if there are 2 samples, we are on one and want to lookback 1.
      // If there are 3 samples, we are on one and want to lookback 2 etc
      uint256 lookback = (activeSamples - 2) * sampleLength;
      return getValueWithLookback(lookback);
    }
    Sample storage __currentSample = _getCurrentSample();
    Sample storage firstSample = _getFirstSample();

    uint256 timeElapsed = __currentSample.timestamp - firstSample.timestamp;

    if (timeElapsed == 0) {
      return __currentSample.value;
    }

    uint256 sampleDiff = __currentSample.cumulativeValue -
      firstSample.cumulativeValue;

    FixedPoint.uq112x112 memory sampleAverage = FixedPoint.fraction(
      sampleDiff,
      timeElapsed
    );

    return sampleAverage.decode();
  }

  function getValueWithLookback(uint256 _lookbackTime)
    public
    view
    returns (uint256)
  {
    // _lookbackTime in is seconds
    uint256 lookbackSamples;
    if (_lookbackTime % sampleLength == 0) {
      // If it divides equally just divide down
      lookbackSamples = _lookbackTime / sampleLength;

      if (lookbackSamples == 0) {
        lookbackSamples = 1;
      }
    } else {
      // If it doesn't divide equally, divide and add 1.
      // Creates a Math.ceil() situation
      lookbackSamples = (_lookbackTime / sampleLength) + 1;
    }

    if (activeSamples < 2) {
      return defaultValue;
    } else if (activeSamples == 2) {
      Sample storage _currentSample = _getCurrentSample();
      return _currentSample.value;
    } else if (lookbackSamples >= activeSamples - 1) {
      // Looking for longer lookback than sampleMemory allows.
      // Just return the full memory average
      return getValue();
    }

    Sample storage __currentSample = _getCurrentSample();
    Sample storage nthSample = _getNthSample(lookbackSamples);

    uint256 timeElapsed = __currentSample.timestamp - nthSample.timestamp;

    if (timeElapsed == 0) {
      return __currentSample.value;
    }

    uint256 sampleDiff = __currentSample.cumulativeValue -
      nthSample.cumulativeValue;

    FixedPoint.uq112x112 memory sampleAverage = FixedPoint.fraction(
      sampleDiff,
      timeElapsed
    );

    return sampleAverage.decode();
  }

  function getLiveSample()
    external
    view
    returns (
      uint64 timestamp,
      uint256 value,
      uint256 cumulativeValue,
      uint256 lastValue
    )
  {
    Sample storage liveSample = samples[_getIndexOfSample(counter)];
    return (
      liveSample.timestamp,
      liveSample.value,
      liveSample.cumulativeValue,
      liveSample.lastValue
    );
  }

  function getSample(uint256 index)
    public
    view
    returns (
      uint64 timestamp,
      uint256 value,
      uint256 cumulativeValue,
      uint256 lastValue
    )
  {
    return (
      samples[index].timestamp,
      samples[index].value,
      samples[index].cumulativeValue,
      samples[index].lastValue
    );
  }

  /*
   * MUTATION METHODS
   */
  function update(uint256 newValue)
    external
    onlyRoleMalt(UPDATER_ROLE, "Must have updater privs")
  {
    /*
     * This function only creates a sample at the end of the sample period.
     * The current sample period just updates the cumulativeValue but doesn't
     * Actually create a sample until the end of the period.
     * This is to protect against flashloan attacks that could try manipulate
     * the samples.
     */
    Sample storage liveSample = samples[_getIndexOfSample(counter)];
    uint64 blockTimestamp = uint64(block.timestamp % 2**64);

    // Deal with first ever sample
    if (liveSample.timestamp == 0) {
      liveSample.timestamp = uint64(block.timestamp);
      liveSample.value = newValue;
      liveSample.lastValue = newValue;
      liveSample.cumulativeValue = newValue;

      cumulativeValue = newValue;
      blockTimestampLast = blockTimestamp;

      activeSamples = activeSamples + 1;
      return;
    }

    uint64 timeElapsed = blockTimestamp - liveSample.timestamp;

    if (timeElapsed < sampleLength) {
      cumulativeValue +=
        liveSample.lastValue *
        (blockTimestamp - blockTimestampLast);
      liveSample.cumulativeValue = cumulativeValue;
      liveSample.lastValue = newValue;

      blockTimestampLast = blockTimestamp;
      return;
    } else if (timeElapsed >= (sampleLength - 1) * sampleMemory) {
      // More than total sample memory has elapsed. Reset with new values
      uint256 addition = liveSample.lastValue * sampleLength;

      uint256 currentCumulative = cumulativeValue;
      uint64 currentTimestamp = blockTimestamp -
        uint64(sampleLength * sampleMemory);

      uint256 tempCount = counter;
      uint256 _sampleMemory = sampleMemory;
      for (uint256 i = 0; i < _sampleMemory; i++) {
        tempCount += 1;
        liveSample = samples[_getIndexOfSample(tempCount)];
        liveSample.timestamp = currentTimestamp;
        liveSample.cumulativeValue = currentCumulative;

        currentCumulative += addition;
        currentTimestamp += uint64(sampleLength);
      }

      // Reset the adding of 'addition' in the final loop
      currentCumulative = liveSample.cumulativeValue;

      tempCount += 1;
      liveSample = samples[_getIndexOfSample(tempCount)];
      liveSample.timestamp = blockTimestamp;
      // Only the most recent values really matter here
      liveSample.value = newValue;
      liveSample.lastValue = newValue;
      liveSample.cumulativeValue = currentCumulative;

      counter = tempCount;
      cumulativeValue = currentCumulative;
      blockTimestampLast = blockTimestamp;
      activeSamples = sampleMemory;
      return;
    }

    uint64 nextSampleTime = liveSample.timestamp + uint64(sampleLength);

    // Finish out the current sample
    cumulativeValue +=
      liveSample.lastValue *
      (nextSampleTime - blockTimestampLast);
    liveSample.cumulativeValue = cumulativeValue;

    liveSample = _createNewSample(nextSampleTime, cumulativeValue);
    timeElapsed = timeElapsed - uint64(sampleLength);

    uint256 elapsedSamples = timeElapsed / sampleLength;

    for (uint256 i = 1; i <= elapsedSamples; i = i + 1) {
      // update
      cumulativeValue += liveSample.lastValue * sampleLength;
      liveSample.cumulativeValue = cumulativeValue;

      uint64 sampleTime = liveSample.timestamp + uint64(sampleLength);

      liveSample = _createNewSample(sampleTime, cumulativeValue);
    }

    cumulativeValue += liveSample.lastValue * (timeElapsed % sampleLength);

    // Now set the value of the current sample to the new value
    liveSample.value = newValue;
    liveSample.lastValue = newValue;
    liveSample.cumulativeValue = cumulativeValue;

    blockTimestampLast = blockTimestamp;

    emit Update(newValue, cumulativeValue);
  }

  /*
   * INTERNAL VIEW METHODS
   */
  function _getIndexOfSample(uint256 _count)
    internal
    view
    returns (uint32 index)
  {
    return uint32(_count % sampleMemory);
  }

  function _getCurrentSample()
    private
    view
    returns (Sample storage currentSample)
  {
    uint256 activeIndex;

    // Active sample is always counter - 1. Counter is the in progress sample
    if (counter > 0) {
      activeIndex = counter - 1;
    }

    uint32 currentSampleIndex = _getIndexOfSample(activeIndex);
    currentSample = samples[currentSampleIndex];
  }

  function _getFirstSample() private view returns (Sample storage firstSample) {
    if (counter + 1 < sampleMemory) {
      return samples[0];
    }
    // no overflow issue. if sampleIndex + 1 overflows, result is still zero.
    firstSample = samples[(counter + 1) % sampleMemory];
  }

  function _getNthSample(uint256 n)
    private
    view
    returns (Sample storage sample)
  {
    require(n < activeSamples - 1, "Not enough samples");
    uint32 sampleIndex = _getIndexOfSample(counter - 1 - n);
    sample = samples[sampleIndex];
  }

  /*
   * INTERNAL METHODS
   */
  function _createNewSample(uint64 sampleTime, uint256 cumulativeValue)
    internal
    returns (Sample storage liveSample)
  {
    uint256 activeIndex;

    // Active sample is always counter - 1. Counter is the in progress sample
    if (counter > 0) {
      activeIndex = counter - 1;
    }
    Sample storage oldSample = samples[_getIndexOfSample(activeIndex)];
    Sample storage previousSample = samples[_getIndexOfSample(counter)];

    if (oldSample.timestamp > 0 && activeSamples > 1) {
      previousSample.value =
        (previousSample.cumulativeValue - oldSample.cumulativeValue) /
        sampleLength;
    }

    counter += 1;
    liveSample = samples[_getIndexOfSample(counter)];
    liveSample.timestamp = sampleTime;
    liveSample.cumulativeValue = cumulativeValue;
    liveSample.value = previousSample.value;
    liveSample.lastValue = previousSample.lastValue;

    if (activeSamples < sampleMemory) {
      // Active samples is how we keep track of how many real samples we have vs default 0 values
      // This is useful for providing data even when full sample set isn't populated yet
      activeSamples = activeSamples + 1;
    }

    blockTimestampLast = sampleTime;
  }

  /*
   * PRIVILEDGED METHODS
   */
  function setSampleLength(uint256 _sampleLength)
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    require(_sampleLength > 0, "Cannot have 0 second sample length");
    sampleLength = _sampleLength;
  }

  function resetLiveSampleTime()
    external
    onlyRoleMalt(ADMIN_ROLE, "Must have admin privs")
  {
    Sample storage liveSample = samples[_getIndexOfSample(counter)];
    liveSample.timestamp = uint64(block.timestamp % 2**64);
  }
}
