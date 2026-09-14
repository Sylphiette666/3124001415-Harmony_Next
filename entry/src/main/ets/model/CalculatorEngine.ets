/** 计算器的纯状态模型，不依赖页面和设备 API。 */
export class CalculatorState {
  display: string = '0';
  expression: string = '';
  error: string = '';
  /** 仅标记本次按键成功产生的结果，供页面同步播报。 */
  calculated: boolean = false;
}

const MAX_INPUT_DIGITS: number = 15;

function copyState(source: CalculatorState): CalculatorState {
  const result = new CalculatorState();
  result.display = source.display;
  result.expression = source.expression;
  result.error = source.error;
  result.calculated = source.calculated;
  return result;
}

function countDigits(text: string): number {
  return text.replace(/[^0-9]/g, '').length;
}

function formatNumber(value: number): string {
  if (value === 0) {
    return '0'; // 规范化 -0
  }
  // 所有运算结果先经 normalizeResult 检查及舍入，输入至多 15 位数字。
  const absolute: number = Math.abs(value);
  if (absolute >= 1e15 || absolute < 1e-9) {
    const scientific: string = value.toExponential(14);
    const parts: string[] = scientific.split('e');
    const mantissa: string = parts[0].replace(/\.?0+$/, '');
    const exponent: number = Number(parts[1]);
    return mantissa + 'e' + (exponent >= 0 ? '+' : '') + exponent.toString();
  }
  return value.toString();
}

/** 将显示文本转换为适合语音播报的中文读法。 */
export function spokenNumber(display: string): string {
  const parts: string[] = display.toLowerCase().split('e');
  const mantissa: string = parts[0].replace(/^-/, '负').replace(/\./g, '点');
  if (parts.length < 2) {
    return mantissa;
  }
  const exponent: string = parts[1].replace(/^\+/, '').replace(/^-/, '负');
  return mantissa + '乘以十的' + exponent + '次方';
}

export class CalculatorEngine {
  private state: CalculatorState = new CalculatorState();
  private current: string = '0';
  private accumulator: number = 0;
  private pendingOperator: string = '';
  private awaitingOperand: boolean = false;
  private editingEntry: boolean = true;
  private resultDisplayed: boolean = false;
  private lastOperator: string = '';
  private lastOperand: number = 0;

  snapshot(): CalculatorState {
    return copyState(this.state);
  }

  press(key: string): CalculatorState {
    this.state.calculated = false;
    if (key === 'AC') {
      this.reset();
    } else if (key === 'CE') {
      this.clearEntry();
    } else if (this.state.error !== '') {
      if (/^[0-9.]$/.test(key)) {
        this.reset();
        if (key === '.') {
          this.inputDecimal();
        } else {
          this.input(key);
        }
      }
    } else if (/^[0-9]$/.test(key)) {
      this.input(key);
    } else if (key === '.') {
      this.inputDecimal();
    } else if (key === '⌫') {
      this.backspace();
    } else if (key === '±') {
      this.toggleSign();
    } else if (key === '%') {
      this.percent();
    } else if (key === '1/x' || key === 'x²' || key === '√') {
      this.unary(key);
    } else if (key === '+' || key === '-' || key === '×' || key === '÷') {
      this.binary(key);
    } else if (key === '=') {
      this.equals();
    }
    this.publish();
    return this.snapshot();
  }

  private publish(): void {
    this.state.display = this.current;
    if (this.state.error !== '') {
      this.state.expression = '';
    }
  }

  private reset(): void {
    this.state = new CalculatorState();
    this.current = '0';
    this.accumulator = 0;
    this.pendingOperator = '';
    this.awaitingOperand = false;
    this.editingEntry = true;
    this.resultDisplayed = false;
    this.lastOperator = '';
    this.lastOperand = 0;
  }

  private clearEntry(): void {
    if (this.state.error !== '') {
      this.reset();
      return;
    }
    this.current = '0';
    this.awaitingOperand = false;
    this.editingEntry = true;
    this.resultDisplayed = false;
    if (this.pendingOperator === '') {
      this.state.expression = '';
      this.lastOperator = '';
    }
  }

  private input(key: string): void {
    if (this.resultDisplayed && this.pendingOperator === '') {
      this.reset();
    }
    if (this.awaitingOperand || !this.editingEntry) {
      this.current = '0';
      this.awaitingOperand = false;
      this.editingEntry = true;
    }
    if (key === '0' && this.current === '0') {
      return;
    }
    if (countDigits(this.current) >= MAX_INPUT_DIGITS) {
      return;
    }
    this.current = this.current === '0' ? key : this.current + key;
    this.resultDisplayed = false;
  }

  private inputDecimal(): void {
    if (this.resultDisplayed && this.pendingOperator === '') {
      this.reset();
    }
    if (this.awaitingOperand || !this.editingEntry) {
      this.current = '0';
      this.awaitingOperand = false;
      this.editingEntry = true;
    }
    if (this.current.indexOf('.') >= 0) {
      return;
    }
    this.current += '.';
    this.resultDisplayed = false;
  }

  private backspace(): void {
    if (!this.editingEntry || this.awaitingOperand || this.resultDisplayed) {
      return;
    }
    if (this.current.length <= 1 || (this.current.length === 2 && this.current[0] === '-')) {
      this.current = '0';
    } else {
      this.current = this.current.substring(0, this.current.length - 1);
      if (this.current === '-') {
        this.current = '0';
      }
    }
    if (Number(this.current) === 0 && this.current[0] === '-') {
      this.current = this.current.substring(1);
    }
  }

  private toggleSign(): void {
    if (this.awaitingOperand) {
      this.current = '0';
      this.awaitingOperand = false;
    }
    if (Number(this.current) === 0) {
      this.current = this.current.replace(/^-/, '');
    } else if (this.current[0] === '-') {
      this.current = this.current.substring(1);
    } else {
      this.current = '-' + this.current;
    }
    // 保留输入/结果状态：结果变号后，下一位数字仍开始新输入。
    if (this.pendingOperator === '' && this.resultDisplayed) {
      this.state.expression = '';
    }
    this.state.calculated = true;
  }

  private binary(operator: string): void {
    const value: number = Number(this.current);
    if (this.pendingOperator !== '' && !this.awaitingOperand) {
      const chained: number = this.calculate(this.accumulator, value, this.pendingOperator);
      if (this.state.error !== '') return;
      this.accumulator = chained;
      this.current = formatNumber(chained);
      this.state.calculated = true;
    } else if (this.pendingOperator === '') {
      this.accumulator = value;
    }
    this.pendingOperator = operator;
    this.awaitingOperand = true;
    this.editingEntry = true;
    this.resultDisplayed = false;
    this.lastOperator = '';
    this.state.expression = formatNumber(this.accumulator) + ' ' + operator;
  }

  private equals(): void {
    let left: number;
    let right: number;
    let operator: string;
    if (this.pendingOperator !== '') {
      left = this.accumulator;
      right = this.awaitingOperand ? this.accumulator : Number(this.current);
      operator = this.pendingOperator;
    } else if (this.lastOperator !== '') {
      left = Number(this.current);
      right = this.lastOperand;
      operator = this.lastOperator;
    } else {
      this.current = formatNumber(Number(this.current));
      this.resultDisplayed = true;
      this.editingEntry = false;
      this.state.expression = this.current + ' =';
      this.state.calculated = true;
      return;
    }
    const result: number = this.calculate(left, right, operator);
    if (this.state.error !== '') return;
    this.current = formatNumber(result);
    this.lastOperator = operator;
    this.lastOperand = right;
    this.pendingOperator = '';
    this.awaitingOperand = false;
    this.editingEntry = false;
    this.resultDisplayed = true;
    this.state.expression = formatNumber(left) + ' ' + operator + ' ' + formatNumber(right) + ' =';
    this.state.calculated = true;
  }

  private calculate(left: number, right: number, operator: string): number {
    let result: number = 0;
    if (operator === '+') result = left + right;
    else if (operator === '-') result = left - right;
    else if (operator === '×') result = left * right;
    else if (operator === '÷') {
      if (right === 0) {
        this.state.error = '不能除以零';
        return 0;
      }
      result = left / right;
    }
    return this.normalizeResult(result);
  }

  private normalizeResult(value: number): number {
    // 舍入本身也可能让接近 Number.MAX_VALUE 的有限数溢出。
    const rounded: number = Number.isFinite(value) ? Number(value.toPrecision(15)) : value;
    if (!Number.isFinite(rounded)) {
      this.state.error = '结果超出可计算范围';
      return 0;
    }
    return rounded === 0 ? 0 : rounded;
  }

  private percent(): void {
    const value: number = Number(this.current);
    let result: number;
    if (this.pendingOperator === '+' || this.pendingOperator === '-') {
      // 先除以 100，避免中间乘法溢出而最终百分比仍处于范围内。
      result = this.accumulator * (value / 100);
    } else {
      result = value / 100;
    }
    const normalized: number = this.normalizeResult(result);
    if (this.state.error !== '') return;
    if (this.pendingOperator === '') {
      this.state.expression = this.current + '%';
      this.lastOperator = '';
    }
    this.current = formatNumber(normalized);
    this.awaitingOperand = false;
    this.editingEntry = false;
    this.resultDisplayed = this.pendingOperator === '';
    this.state.calculated = true;
  }

  private unary(key: string): void {
    const value: number = Number(this.current);
    let result: number;
    if (key === '1/x') {
      if (value === 0) {
        this.state.error = '不能除以零';
        return;
      }
      result = 1 / value;
    } else if (key === 'x²') {
      result = value * value;
    } else {
      if (value < 0) {
        this.state.error = '负数不能开平方';
        return;
      }
      result = Math.sqrt(value);
    }
    const normalized: number = this.normalizeResult(result);
    if (this.state.error !== '') return;
    if (this.pendingOperator === '') {
      this.state.expression = key + '(' + this.current + ')';
      this.lastOperator = '';
    }
    this.current = formatNumber(normalized);
    this.awaitingOperand = false;
    this.editingEntry = false;
    this.resultDisplayed = this.pendingOperator === '';
    this.state.calculated = true;
  }
}
