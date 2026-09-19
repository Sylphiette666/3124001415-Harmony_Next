import abilityTest from './Ability.test';
import cardStoreTest from './CardStore.test';
import cardFlowTest from './CardFlow.test';
import profileFlowTest from './ProfileFlow.test';
import calculatorEngineTest from './CalculatorEngine.test';
import calculatorFlowTest from './CalculatorFlow.test';
import weatherFlowTest from './WeatherFlow.test';

export default function testsuite() {
  abilityTest();
  cardStoreTest();
  cardFlowTest();
  profileFlowTest();
  calculatorEngineTest();
  calculatorFlowTest();
  weatherFlowTest();
}
