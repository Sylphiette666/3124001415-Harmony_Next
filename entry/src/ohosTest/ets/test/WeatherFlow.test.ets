import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry, Component, Driver, ON, On } from '@kit.TestKit';

class WeatherUi {
  driver: Driver = Driver.create();
  bundle: string;
  constructor(bundle: string) { this.bundle = bundle; }
  selector(id: string): On { return ON.id(id).inWindow(this.bundle); }
  async wait(id: string, timeout: number = 8000): Promise<Component> {
    const component = await this.driver.waitForComponent(this.selector(id), timeout);
    if (!component) { throw new Error('天气控件未出现：' + id); }
    return component;
  }
  async reveal(id: string, scrollId: string): Promise<Component> {
    const direct = await this.driver.findComponent(this.selector(id));
    if (direct) { return direct; }
    const found = await (await this.wait(scrollId)).scrollSearch(this.selector(id));
    if (!found) { throw new Error('滚动后找不到天气控件：' + id); }
    return found;
  }
  async awaitReport(): Promise<void> {
    // A timeout/offline error must fail this live-network acceptance test.
    // Deterministic error-path coverage is provided by scripts/test-weather.cjs.
    for (let i = 0; i < 40; i++) {
      const error = await this.driver.findComponent(this.selector('WeatherError'));
      if (error) { throw new Error('设备天气查询失败：' + await error.getText()); }
      const temperature = await this.driver.findComponent(this.selector('WeatherTemperature'));
      const loading = await this.driver.findComponent(this.selector('WeatherLoading'));
      if (temperature && !loading) {
        expect((await temperature.getText()).includes('°')).assertTrue();
        return;
      }
      await this.driver.delayMs(500);
    }
    throw new Error('等待天气结果超时');
  }
}

export default function weatherFlowTest() {
  describe('WeatherUi', () => {
    it('opensQueriesRefreshesForecastAndReturns', 0, async () => {
      const args = abilityDelegatorRegistry.getArguments();
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({ bundleName: args.bundleName, abilityName: 'EntryAbility' });
      const ui = new WeatherUi(args.bundleName);
      let entered = false;
      try {
        await ui.wait('HomeScroll');
        await (await ui.reveal('OpenWeatherButton', 'HomeScroll')).click(); entered = true;
        await ui.wait('WeatherPage');
        await ui.wait('WeatherProvinceSelect'); await ui.wait('WeatherCitySelect');
        await ui.awaitReport();
        const city = await (await ui.wait('WeatherCityName')).getText();
        expect(city.length > 0).assertTrue();
        await ui.wait('WeatherHumidity'); await ui.wait('WeatherWind'); await ui.wait('WeatherUpdatedAt');
        await (await ui.wait('WeatherQueryButton')).click(); await ui.awaitReport();
        expect(await (await ui.wait('WeatherCityName')).getText()).assertEqual(city);
        await ui.reveal('WeatherForecast', 'WeatherScroll');
        await (await ui.reveal('WeatherRefreshButton', 'WeatherScroll')).click();
        await ui.driver.delayMs(1000);
        // Scroll back to the weather data to inspect the refreshed state.
        await ui.reveal('WeatherTemperature', 'WeatherScroll'); await ui.awaitReport();
      } finally {
        if (entered) { try { await (await ui.wait('WeatherBackButton')).click(); } catch { /* Preserve test failure. */ } }
      }
    });
  });
}
