import abilityTest from './Ability.test';
import cardStoreTest from './CardStore.test';
import cardFlowTest from './CardFlow.test';
import profileFlowTest from './ProfileFlow.test';

export default function testsuite() {
  abilityTest();
  cardStoreTest();
  cardFlowTest();
  profileFlowTest();
}
