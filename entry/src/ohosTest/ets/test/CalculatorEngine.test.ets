import { describe, it, expect } from '@ohos/hypium';
import { CalculatorEngine, CalculatorState, spokenNumber } from '../../../main/ets/model/CalculatorEngine';

function pressKeys(calculator: CalculatorEngine, keys: string[]): CalculatorState {
  keys.forEach((key: string) => { calculator.press(key); });
  return calculator.snapshot();
}

function enterNumber(calculator: CalculatorEngine, digits: string): void {
  for (let i = 0; i < digits.length; i++) {
    calculator.press(digits[i]);
  }
}

function largeNumber(calculator: CalculatorEngine): void {
  enterNumber(calculator, '100000000000000');
  pressKeys(calculator, ['x²', 'x²', 'x²', 'x²']); // 10^224，仍是有限数
}

export default function calculatorEngineTest() {
  describe('CalculatorEngine', () => {
    it('chainsLeftToRightAndRepeatsEquals', 0, () => {
      const c = new CalculatorEngine();
      expect(pressKeys(c, ['2', '+', '3', '×']).display).assertEqual('5');
      expect(c.press('4').display).assertEqual('4');
      expect(c.press('=').display).assertEqual('20');
      expect(c.press('=').display).assertEqual('80');
    });

    it('repeatsLastAdditionAndImplicitOperand', 0, () => {
      const c = new CalculatorEngine();
      expect(pressKeys(c, ['5', '+', '2', '=']).display).assertEqual('7');
      expect(c.press('=').display).assertEqual('9');
      expect(pressKeys(c, ['AC', '3', '+', '=']).display).assertEqual('6');
      expect(c.press('=').display).assertEqual('9');
    });

    it('repeatsSubtractionAndDivision', 0, () => {
      const c = new CalculatorEngine();
      expect(pressKeys(c, ['9', '-', '2', '=', '=']).display).assertEqual('5');
      expect(pressKeys(c, ['AC', '8', '÷', '2', '=', '=']).display).assertEqual('2');
    });

    it('replacesPendingOperator', 0, () => {
      const c = new CalculatorEngine();
      expect(pressKeys(c, ['8', '+', '×', '2', '=']).display).assertEqual('16');
      expect(pressKeys(c, ['AC', '8', '×', '-', '2', '=']).display).assertEqual('6');
    });

    it('handlesAdditionAndSubtractionPercent', 0, () => {
      const c = new CalculatorEngine();
      enterNumber(c, '200');
      expect(pressKeys(c, ['+', '1', '0', '%']).display).assertEqual('20');
      expect(c.press('=').display).assertEqual('220');
      expect(c.press('=').display).assertEqual('240');
      c.press('AC'); enterNumber(c, '200');
      expect(pressKeys(c, ['-', '1', '0', '%', '=']).display).assertEqual('180');
    });

    it('handlesMultiplicationDivisionAndStandalonePercent', 0, () => {
      const c = new CalculatorEngine();
      expect(pressKeys(c, ['8', '×', '5', '%', '=']).display).assertEqual('0.4');
      expect(pressKeys(c, ['AC', '8', '÷', '5', '%', '=']).display).assertEqual('160');
      expect(pressKeys(c, ['AC', '5', '0', '%']).display).assertEqual('0.5');
    });

    it('avoidsDecimalFloatingPointNoise', 0, () => {
      const c = new CalculatorEngine();
      expect(pressKeys(c, ['0', '.', '1', '+', '0', '.', '2', '=']).display).assertEqual('0.3');
      expect(pressKeys(c, ['AC', '1', '÷', '3', '=']).display).assertEqual('0.333333333333333');
      expect(pressKeys(c, ['AC', '0', '.', '3', '-', '0', '.', '2', '=']).display).assertEqual('0.1');
    });

    it('clearsOnlyCurrentOperandWithCE', 0, () => {
      const c = new CalculatorEngine();
      expect(pressKeys(c, ['8', '+', '9', 'CE']).display).assertEqual('0');
      expect(c.snapshot().expression).assertEqual('8 +');
      expect(pressKeys(c, ['2', '=']).display).assertEqual('10');
      expect(pressKeys(c, ['AC', '8', '+', 'CE', '=']).display).assertEqual('8');
      expect(pressKeys(c, ['CE', '=']).display).assertEqual('0');
    });

    it('resetsAllStateWithAC', 0, () => {
      const c = new CalculatorEngine();
      pressKeys(c, ['8', '+', '9', '=', 'AC']);
      expect(c.snapshot().display).assertEqual('0');
      expect(c.snapshot().expression).assertEqual('');
      expect(c.snapshot().error).assertEqual('');
      expect(c.press('=').display).assertEqual('0');
    });

    it('editsDigitsAndDecimalWithBackspace', 0, () => {
      const c = new CalculatorEngine();
      expect(pressKeys(c, ['1', '2', '.', '3', '⌫']).display).assertEqual('12.');
      expect(c.press('⌫').display).assertEqual('12');
      expect(pressKeys(c, ['±', '⌫']).display).assertEqual('-1');
      expect(c.press('⌫').display).assertEqual('0');
      expect(pressKeys(c, ['8', '=', '⌫']).display).assertEqual('8');
      expect(pressKeys(c, ['+', '⌫']).display).assertEqual('8');
    });

    it('ignoresRepeatedDecimalAndLeadingZeroes', 0, () => {
      const c = new CalculatorEngine();
      expect(pressKeys(c, ['0', '0', '.', '.', '2', '.', '5']).display).assertEqual('0.25');
      expect(pressKeys(c, ['=', '.', '5']).display).assertEqual('0.5');
    });

    it('limitsInputToFifteenDigits', 0, () => {
      const c = new CalculatorEngine();
      enterNumber(c, '1234567890123456789');
      expect(c.snapshot().display).assertEqual('123456789012345');
      c.press('AC'); enterNumber(c, '0.1234567890123456789');
      expect(c.snapshot().display).assertEqual('0.12345678901234');
    });

    it('reportsDivisionByZeroAndRecoversWithDigit', 0, () => {
      const c = new CalculatorEngine();
      expect(pressKeys(c, ['8', '÷', '0', '=']).error).assertEqual('不能除以零');
      expect(c.press('+').error).assertEqual('不能除以零');
      expect(c.press('2').display).assertEqual('2');
      expect(c.snapshot().error).assertEqual('');
      expect(pressKeys(c, ['+', '3', '=']).display).assertEqual('5');
      expect(pressKeys(c, ['AC', '1/x']).error).assertEqual('不能除以零');
      expect(c.press('CE').error).assertEqual('');
    });

    it('startsDecimalEntryAfterError', 0, () => {
      const c = new CalculatorEngine();
      pressKeys(c, ['1', '÷', '0', '=']);
      expect(c.press('.').display).assertEqual('0.');
      expect(c.snapshot().error).assertEqual('');
      expect(pressKeys(c, ['5', '+', '1', '=']).display).assertEqual('1.5');
    });

    it('reportsNegativeSquareRootAndRestoresWithAC', 0, () => {
      const c = new CalculatorEngine();
      expect(pressKeys(c, ['9', '±', '√']).error).assertEqual('负数不能开平方');
      expect(c.press('AC').error).assertEqual('');
      expect(pressKeys(c, ['9', '√']).display).assertEqual('3');
    });

    it('reportsUnaryAndBinaryOverflow', 0, () => {
      const c = new CalculatorEngine();
      largeNumber(c);
      expect(c.snapshot().display).assertEqual('1e+224');
      expect(c.press('x²').error).assertEqual('结果超出可计算范围');
      c.press('AC'); largeNumber(c);
      expect(pressKeys(c, ['×', '=']).error).assertEqual('结果超出可计算范围');
      expect(c.snapshot().display.indexOf('Infinity') < 0).assertTrue();
      expect(c.snapshot().display.indexOf('NaN') < 0).assertTrue();
    });

    it('reportsPercentageOverflowWithoutShowingFalseZero', 0, () => {
      const c = new CalculatorEngine();
      largeNumber(c);
      expect(pressKeys(c, ['+', '%']).error).assertEqual('结果超出可计算范围');
      expect(c.snapshot().display).assertEqual('1e+224');
      expect(c.press('CE').display).assertEqual('0');
      expect(c.snapshot().error).assertEqual('');
    });

    it('normalizesNegativeZeroAndPreservesEditableSign', 0, () => {
      const c = new CalculatorEngine();
      expect(c.press('±').display).assertEqual('0');
      expect(pressKeys(c, ['.', '0', '±']).display).assertEqual('0.0');
      expect(pressKeys(c, ['5', '±']).display).assertEqual('-0.05');
      expect(c.press('⌫').display).assertEqual('0.0');
      expect(pressKeys(c, ['AC', '3', '±', '2']).display).assertEqual('-32');
      expect(pressKeys(c, ['×', '0', '=']).display).assertEqual('0');
    });

    it('startsNewInputAfterSignedResult', 0, () => {
      const c = new CalculatorEngine();
      expect(pressKeys(c, ['2', '+', '3', '=', '±']).display).assertEqual('-5');
      expect(c.press('4').display).assertEqual('4');
      expect(c.press('=').display).assertEqual('4');
      expect(pressKeys(c, ['√', '±', '.', '5']).display).assertEqual('0.5');
    });

    it('supportsUnaryOperationsAndReplacesTheirResultOnInput', 0, () => {
      const c = new CalculatorEngine();
      expect(pressKeys(c, ['4', '1/x']).display).assertEqual('0.25');
      expect(c.press('2').display).assertEqual('2');
      expect(c.press('x²').display).assertEqual('4');
      expect(c.press('3').display).assertEqual('3');
      expect(pressKeys(c, ['AC', '8', '+', '9', '√', '=']).display).assertEqual('11');
      expect(pressKeys(c, ['AC', '8', '+', '9', '√', '2', '=']).display).assertEqual('10');
    });

    it('usesCompactScientificNotation', 0, () => {
      const c = new CalculatorEngine();
      enterNumber(c, '100000000000000');
      expect(pressKeys(c, ['×', '1', '0', '=']).display).assertEqual('1e+15');
      expect(c.press('1/x').display).assertEqual('1e-15');
      expect(c.press('1/x').display).assertEqual('1e+15');
    });

    it('returnsIndependentStateObjects', 0, () => {
      const c = new CalculatorEngine();
      const first: CalculatorState = c.snapshot();
      const second: CalculatorState = c.press('1');
      first.display = 'tampered';
      second.expression = 'tampered';
      expect(c.snapshot().display).assertEqual('1');
      expect(c.snapshot().expression).assertEqual('');
    });

    it('speaksSignsDecimalsAndScientificExponents', 0, () => {
      expect(spokenNumber('-1.2e+3')).assertEqual('负1点2乘以十的3次方');
      expect(spokenNumber('1e-15')).assertEqual('1乘以十的负15次方');
      expect(spokenNumber('-0.25')).assertEqual('负0点25');
      expect(spokenNumber('20')).assertEqual('20');
    });

    it('emitsIntermediateAndEqualsResultEvents', 0, () => {
      const c = new CalculatorEngine();
      expect(pressKeys(c, ['2', '+']).calculated).assertEqual(false);
      expect(c.press('3').calculated).assertEqual(false);
      const intermediate: CalculatorState = c.press('×');
      expect(intermediate.calculated).assertTrue();
      expect(intermediate.display).assertEqual('5');
      expect(c.press('4').calculated).assertEqual(false);
      expect(c.press('=').calculated).assertTrue();
      expect(c.snapshot().display).assertEqual('20');
      expect(c.press('=').calculated).assertTrue();
      expect(c.snapshot().display).assertEqual('80');
      expect(pressKeys(c, ['AC', '6', '=']).calculated).assertTrue();
    });

    it('emitsSignUnaryAndPercentResultEvents', 0, () => {
      const c = new CalculatorEngine();
      pressKeys(c, ['5', '=']);
      const signed: CalculatorState = c.press('±');
      expect(signed.calculated).assertTrue();
      expect(signed.display).assertEqual('-5');
      expect(c.press('x²').calculated).assertTrue();
      expect(c.press('√').calculated).assertTrue();
      expect(c.press('1/x').calculated).assertTrue();
      expect(c.press('%').calculated).assertTrue();
      expect(c.snapshot().display).assertEqual('0.002');
    });

    it('clearsResultEventsForNewInputClearsAndErrors', 0, () => {
      const c = new CalculatorEngine();
      const previous: CalculatorState = pressKeys(c, ['4', '=']);
      expect(c.press('2').calculated).assertEqual(false);
      expect(previous.calculated).assertTrue();
      expect(pressKeys(c, ['=', 'CE']).calculated).assertEqual(false);
      expect(pressKeys(c, ['=', 'AC']).calculated).assertEqual(false);
      expect(pressKeys(c, ['8', '÷', '0', '=']).calculated).assertEqual(false);
      expect(c.snapshot().error).assertEqual('不能除以零');
      expect(c.press('±').calculated).assertEqual(false);
      expect(c.press('.').calculated).assertEqual(false);
      expect(pressKeys(c, ['5', '±', '√']).calculated).assertEqual(false);
      expect(c.snapshot().error).assertEqual('负数不能开平方');
    });
  });
}
