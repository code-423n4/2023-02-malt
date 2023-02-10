// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../libraries/uniswap/FixedPoint.sol";

import "../Permissions.sol";

/// @title Dual Moving Average
/// @author 0xScotch <scotch@malt.money>
/// @notice For tracking the average of two data stream in the same sample bins
/// @dev Based on the cumulativeValue mechanism for TWAP in uniswapV2
contract DualMovingAverage is Permissions {
  using FixedPoint for *;

  struct Sample {
    uint64 timestamp;
    uint256 value;
    uint256 valueTwo;
    uint256 cumulativeValue;
    uint256 cumulativeValueTwo;
    uint256 lastValue;
    uint256 lastValueTwo;
  }

  bytes32 public immutable UPDATER_ROLE;

  uint256 public sampleLength;
  uint256 public sampleMemory;
  uint256 public cumulativeValue;
  uint256 public cumulativeValueTwo;
  uint256 public defaultValue;
  uint256 public defaultValueTwo;

  uint64 public blockTimestampLast;

  uint256 private counter;
  uint256 public activeSamples;

  Sample[] private samples;

  event Update(
    uint256 value,
    uint256 cumulativeValue,
    uint256 valueTwo,
    uint256 cumulativeValueTwo
  );

  constructor(
    address _repository,
    address initialAdmin,
    uint256 _sampleLength, // eg 5min represented as seconds
    uint256 _sampleMemory,
    uint256 _defaultValue,
    uint256 _defaultValueTwo,
    address _updater
  ) {
    require(_repository != address(0), "MA: Repo addr(0)");
    require(initialAdmin != address(0), "MA: Admin addr(0)");
    require(_sampleMemory > 1, "MA: SampleMemory > 1");

    _initialSetup(_repository);

    // setup UPDATER_ROLE
    UPDATER_ROLE = 0x73e573f9566d61418a34d5de3ff49360f9c51fec37f7486551670290f6285dab;
    _roleSetup(
      0x73e573f9566d61418a34d5de3ff49360f9c51fec37f7486551670290f6285dab,
      initialAdmin
    );
    _grantRole(
      0x73e573f9566d61418a34d5de3ff49360f9c51fec37f7486551670290f6285dab,
      _updater
    );

    sampleLength = _sampleLength;
    sampleMemory = _sampleMemory;
    defaultValue = _defaultValue;
    defaultValueTwo = _defaultValueTwo;

    for (uint256 i = 0; i < _sampleMemory; i++) {
      samples.push();
    }
  }

  /*
   * PUBLIC VIEW METHODS
   */
  function getValue() public view returns (uint256, uint256) {
    if (activeSamples < 2) {
      return (defaultValue, defaultValueTwo);
    } else if (activeSamples == 2) {
      Sample storage _currentSample = _getCurrentSample();
      return (_currentSample.value, _currentSample.valueTwo);
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
      return (__currentSample.value, __currentSample.valueTwo);
    }

    uint256 sampleDiff = __currentSample.cumulativeValue -
      firstSample.cumulativeValue;
    uint256 sampleDiffTwo = __currentSample.cumulativeValueTwo -
      firstSample.cumulativeValueTwo;

    FixedPoint.uq112x112 memory sampleAverage = FixedPoint.fraction(
      sampleDiff,
      timeElapsed
    );
    FixedPoint.uq112x112 memory sampleAverageTwo = FixedPoint.fraction(
      sampleDiffTwo,
      timeElapsed
    );

    return (sampleAverage.decode(), sampleAverageTwo.decode());
  }

  function getValueWithLookback(uint256 _lookbackTime)
    public
    view
    returns (uint256, uint256)
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
      return (defaultValue, defaultValueTwo);
    } else if (activeSamples == 2) {
      Sample storage _currentSample = _getCurrentSample();
      return (_currentSample.value, _currentSample.valueTwo);
    } else if (lookbackSamples >= activeSamples - 1) {
      // Looking for longer lookback than sampleMemory allows.
      // Just return the full memory average
      return getValue();
    }

    Sample storage __currentSample = _getCurrentSample();
    Sample storage nthSample = _getNthSample(lookbackSamples);

    uint256 timeElapsed = __currentSample.timestamp - nthSample.timestamp;

    if (timeElapsed == 0) {
      return (__currentSample.value, __currentSample.valueTwo);
    }

    uint256 sampleDiff = __currentSample.cumulativeValue -
      nthSample.cumulativeValue;
    uint256 sampleDiffTwo = __currentSample.cumulativeValueTwo -
      nthSample.cumulativeValueTwo;

    FixedPoint.uq112x112 memory sampleAverage = FixedPoint.fraction(
      sampleDiff,
      timeElapsed
    );
    FixedPoint.uq112x112 memory sampleAverageTwo = FixedPoint.fraction(
      sampleDiffTwo,
      timeElapsed
    );

    return (sampleAverage.decode(), sampleAverageTwo.decode());
  }

  function getLiveSample()
    external
    view
    returns (
      uint64 timestamp,
      uint256 value,
      uint256 valueTwo,
      uint256 cumulativeValue,
      uint256 cumulativeValueTwo,
      uint256 lastValue,
      uint256 lastValueTwo
    )
  {
    Sample storage liveSample = samples[_getIndexOfSample(counter)];
    return (
      liveSample.timestamp,
      liveSample.value,
      liveSample.valueTwo,
      liveSample.cumulativeValue,
      liveSample.cumulativeValueTwo,
      liveSample.lastValue,
      liveSample.lastValueTwo
    );
  }

  function getSample(uint256 index)
    public
    view
    returns (
      uint64 timestamp,
      uint256 value,
      uint256 valueTwo,
      uint256 cumulativeValue,
      uint256 cumulativeValueTwo,
      uint256 lastValue,
      uint256 lastValueTwo
    )
  {
    return (
      samples[index].timestamp,
      samples[index].value,
      samples[index].valueTwo,
      samples[index].cumulativeValue,
      samples[index].cumulativeValueTwo,
      samples[index].lastValue,
      samples[index].lastValueTwo
    );
  }

  /*
   * MUTATION METHODS
   */
  function update(uint256 newValue, uint256 newValueTwo)
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
      liveSample.valueTwo = newValueTwo;
      liveSample.lastValue = newValue;
      liveSample.lastValueTwo = newValueTwo;
      liveSample.cumulativeValue = newValue;
      liveSample.cumulativeValueTwo = newValueTwo;

      cumulativeValue = newValue;
      cumulativeValueTwo = newValueTwo;
      blockTimestampLast = blockTimestamp;

      activeSamples = activeSamples + 1;
      return;
    }

    uint64 timeElapsed = blockTimestamp - liveSample.timestamp;

    if (timeElapsed < sampleLength) {
      uint256 timeDiff = blockTimestamp - blockTimestampLast;
      cumulativeValue += liveSample.lastValue * timeDiff;
      cumulativeValueTwo += liveSample.lastValueTwo * timeDiff;
      liveSample.cumulativeValue = cumulativeValue;
      liveSample.cumulativeValueTwo = cumulativeValueTwo;
      liveSample.lastValue = newValue;
      liveSample.lastValueTwo = newValueTwo;

      blockTimestampLast = blockTimestamp;
      return;
    } else if (timeElapsed >= (sampleLength - 1) * sampleMemory) {
      // More than total sample memory has elapsed. Reset with new values
      uint256 addition = liveSample.lastValue * sampleLength;
      uint256 additionTwo = liveSample.lastValueTwo * sampleLength;

      uint256 currentCumulative = cumulativeValue;
      uint256 currentCumulativeTwo = cumulativeValueTwo;
      uint64 currentTimestamp = blockTimestamp -
        uint64(sampleLength * sampleMemory);

      uint256 tempCount = counter;
      uint256 _sampleMemory = sampleMemory;
      for (uint256 i = 0; i < _sampleMemory; i++) {
        tempCount += 1;
        liveSample = samples[_getIndexOfSample(tempCount)];
        liveSample.timestamp = currentTimestamp;
        liveSample.cumulativeValue = currentCumulative;
        liveSample.cumulativeValueTwo = currentCumulativeTwo;

        currentCumulative += addition;
        currentCumulativeTwo += additionTwo;
        currentTimestamp += uint64(sampleLength);
      }

      // Reset the adding of 'addition' in the final loop
      currentCumulative = liveSample.cumulativeValue;
      currentCumulativeTwo = liveSample.cumulativeValueTwo;

      tempCount += 1;
      liveSample = samples[_getIndexOfSample(tempCount)];
      liveSample.timestamp = blockTimestamp;
      // Only the most recent values really matter here
      liveSample.value = newValue;
      liveSample.valueTwo = newValueTwo;
      liveSample.lastValue = newValue;
      liveSample.lastValueTwo = newValueTwo;
      liveSample.cumulativeValue = currentCumulative;
      liveSample.cumulativeValueTwo = currentCumulativeTwo;

      counter = tempCount;
      cumulativeValue = currentCumulative;
      cumulativeValueTwo = currentCumulativeTwo;
      blockTimestampLast = blockTimestamp;
      activeSamples = sampleMemory;
      return;
    }

    uint64 nextSampleTime = liveSample.timestamp + uint64(sampleLength);
    uint256 timeDiff = (nextSampleTime - blockTimestampLast);

    // Finish out the current sample
    cumulativeValue += liveSample.lastValue * timeDiff;
    cumulativeValueTwo += liveSample.lastValueTwo * timeDiff;
    liveSample.cumulativeValue = cumulativeValue;
    liveSample.cumulativeValueTwo = cumulativeValueTwo;

    liveSample = _createNewSample(
      nextSampleTime,
      cumulativeValue,
      cumulativeValueTwo
    );
    timeElapsed = timeElapsed - uint64(sampleLength);

    uint256 elapsedSamples = timeElapsed / sampleLength;

    for (uint256 i = 1; i <= elapsedSamples; i = i + 1) {
      // update
      cumulativeValue += liveSample.lastValue * sampleLength;
      cumulativeValueTwo += liveSample.lastValueTwo * sampleLength;
      liveSample.cumulativeValue = cumulativeValue;
      liveSample.cumulativeValueTwo = cumulativeValueTwo;

      uint64 sampleTime = liveSample.timestamp + uint64(sampleLength);

      liveSample = _createNewSample(
        sampleTime,
        cumulativeValue,
        cumulativeValueTwo
      );
    }

    uint256 remainder = timeElapsed % sampleLength;
    cumulativeValue += liveSample.lastValue * remainder;
    cumulativeValueTwo += liveSample.lastValueTwo * remainder;

    // Now set the value of the current sample to the new value
    liveSample.value = newValue;
    liveSample.valueTwo = newValueTwo;
    liveSample.lastValue = newValue;
    liveSample.lastValueTwo = newValueTwo;
    liveSample.cumulativeValue = cumulativeValue;
    liveSample.cumulativeValueTwo = cumulativeValueTwo;

    blockTimestampLast = blockTimestamp;

    emit Update(newValue, cumulativeValue, newValueTwo, cumulativeValueTwo);
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
  function _createNewSample(
    uint64 sampleTime,
    uint256 cumulativeValue,
    uint256 cumulativeValueTwo
  ) internal returns (Sample storage liveSample) {
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
      previousSample.valueTwo =
        (previousSample.cumulativeValueTwo - oldSample.cumulativeValueTwo) /
        sampleLength;
    }

    counter += 1;
    liveSample = samples[_getIndexOfSample(counter)];
    liveSample.timestamp = sampleTime;
    liveSample.cumulativeValue = cumulativeValue;
    liveSample.cumulativeValueTwo = cumulativeValueTwo;
    liveSample.value = previousSample.value;
    liveSample.valueTwo = previousSample.valueTwo;
    liveSample.lastValue = previousSample.lastValue;
    liveSample.lastValueTwo = previousSample.lastValueTwo;

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
