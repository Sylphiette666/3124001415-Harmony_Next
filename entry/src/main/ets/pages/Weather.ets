import { common } from '@kit.AbilityKit';
import { ACCENT, INK, MUTED, PAGE_BG } from '../model/CourseData';
import { citiesInProvince, findWeatherCity, WEATHER_PROVINCES } from '../model/WeatherCities';
import { ForecastDay, WeatherCity, WeatherReport, forecastDateLabel, weatherIconPath } from '../model/WeatherData';
import { WeatherController, WeatherViewState } from '../model/WeatherController';
import { WeatherStore } from '../model/WeatherStore';
import { WeatherHttpClient } from '../services/WeatherHttpClient';

@Component
struct WeatherReportCard {
  @Prop report: WeatherReport = new WeatherReport();
  @Prop cached: boolean = false;
  build() {
    Column({ space: 16 }) {
      Row() {
        Column({ space: 5 }) {
          Text(this.report.cityName).id('WeatherCityName').fontSize(27).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Text(this.report.province).fontSize(13).fontColor('#C6E3EA')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text(this.cached ? '历史缓存' : '当前天气').fontSize(12).fontColor('#E7F6F8')
          .padding({ left: 10, right: 10, top: 6, bottom: 6 }).backgroundColor('#346274').borderRadius(20)
      }.width('100%')
      Row() {
        Column({ space: 4 }) {
          Text(this.report.temperature).id('WeatherTemperature').fontSize(68).fontWeight(FontWeight.Medium)
            .fontColor(Color.White).maxLines(1).minFontSize(38).maxFontSize(68)
          Text(this.report.condition).id('WeatherCondition').fontSize(18).fontColor('#ECF6F7')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Image($rawfile('weather/' + weatherIconPath(this.report.icon))).width(92).height(92).objectFit(ImageFit.Contain)
          .accessibilityText(this.report.condition)
      }.width('100%')
      Row() {
        Column({ space: 6 }) {
          Text('体感').fontColor('#C6E3EA').fontSize(12)
          Text(this.report.feelsLike).fontColor(Color.White).fontSize(18)
        }.layoutWeight(1)
        Column({ space: 6 }) {
          Text('湿度').fontColor('#C6E3EA').fontSize(12)
          Text(this.report.humidity).id('WeatherHumidity').fontColor(Color.White).fontSize(18)
        }.layoutWeight(1)
        Column({ space: 6 }) {
          Text(this.report.direction).fontColor('#C6E3EA').fontSize(12)
          Text(this.report.wind).id('WeatherWind').fontColor(Color.White).fontSize(16)
        }.layoutWeight(1)
      }.width('100%').padding({ top: 12, bottom: 12 }).backgroundColor('#285364').borderRadius(16)
      Text('数据时间 ' + this.report.observedAt.replace('T', ' ') + ' · 北京时间')
        .id('WeatherUpdatedAt').fontSize(11).fontColor('#C6E3EA').width('100%')
    }.width('100%').padding(22).backgroundColor('#183F53').borderRadius(24)
  }
}

@Component
struct WeatherForecastRow {
  @Prop day: ForecastDay = new ForecastDay();
  build() {
    Row({ space: 12 }) {
      Column({ space: 5 }) {
        Text(forecastDateLabel(this.day.date)).fontSize(15).fontWeight(FontWeight.Medium).fontColor(INK)
        Text(this.day.date.slice(5).replace('-', '/')).fontSize(11).fontColor(MUTED)
      }.width(43).alignItems(HorizontalAlign.Start)
      Image($rawfile('weather/' + weatherIconPath(this.day.icon))).width(34).height(34).objectFit(ImageFit.Contain)
      Column({ space: 5 }) {
        Text(this.day.condition).fontSize(14).fontColor(INK)
        Text('降水 ' + this.day.rain + ' · ' + this.day.wind).fontSize(11).fontColor(MUTED)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text(this.day.low + ' / ' + this.day.high).fontSize(15).fontWeight(FontWeight.Medium).fontColor(INK)
    }.width('100%').padding({ top: 13, bottom: 13 })
  }
}

@Entry
@Component
struct Weather {
  @State view: WeatherViewState = new WeatherViewState();
  @State province: string = findWeatherCity('').province;
  @State cityId: string = findWeatherCity('').id;
  @State cities: WeatherCity[] = citiesInProvince(findWeatherCity('').province);
  private controller: WeatherController | undefined = undefined;
  private store: WeatherStore | undefined = undefined;

  onPageShow(): void {
    if (!this.store) {
      this.store = new WeatherStore(this.getUIContext().getHostContext() as common.UIAbilityContext);
      try {
        const city = findWeatherCity(this.store.lastCity());
        this.province = city.province; this.cityId = city.id; this.cities = citiesInProvince(city.province);
      } catch { /* A storage failure must not prevent live queries. */ }
    }
    this.controller = new WeatherController(new WeatherHttpClient(), this.store, (state: WeatherViewState) => { this.view = state; });
    this.query();
  }
  onPageHide(): void { this.release(); }
  aboutToDisappear(): void { this.release(); }
  private release(): void { this.controller?.dispose(); this.controller = undefined; }
  private query(): void { this.controller?.load(findWeatherCity(this.cityId)); }
  private provinceOptions(): SelectOption[] { return WEATHER_PROVINCES.map((name: string): SelectOption => { return { value: name }; }); }
  private cityOptions(): SelectOption[] { return this.cities.map((city: WeatherCity): SelectOption => { return { value: city.name }; }); }
  private changeProvince(index: number): void {
    this.province = WEATHER_PROVINCES[index];
    this.cities = citiesInProvince(this.province); this.cityId = this.cities[0].id;
  }
  private async openSource(url: string): Promise<void> {
    try { await (this.getUIContext().getHostContext() as common.UIAbilityContext).openLink(url); }
    catch {
      try { this.getUIContext().getPromptAction().showToast({ message: '请在浏览器访问 ' + url }); }
      catch { /* The ability may have closed while the browser was starting. */ }
    }
  }

  build() {
    Column() {
      Row({ space: 14 }) {
        Button('‹', { type: ButtonType.Normal }).id('WeatherBackButton').fontSize(30).fontColor(INK)
          .width(40).height(42).backgroundColor(Color.White).borderRadius(12)
          .accessibilityText('返回首页').onClick(() => this.getUIContext().getRouter().back())
        Column({ space: 3 }) {
          Text('天气预报').fontSize(24).fontWeight(FontWeight.Bold).fontColor(INK)
          Text('晴雨早知道，出行有准备').fontSize(12).fontColor(MUTED)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%').padding({ left: 20, right: 20, top: 14, bottom: 14 })
      Scroll() {
        Column({ space: 18 }) {
          Column({ space: 12 }) {
            Text('选择省市').fontSize(15).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
            Row({ space: 10 }) {
              Select(this.provinceOptions()).id('WeatherProvinceSelect')
                .selected(WEATHER_PROVINCES.indexOf(this.province)).value(this.province)
                .font({ size: 14 }).fontColor(INK).backgroundColor(PAGE_BG).borderRadius(12).layoutWeight(1)
                .onSelect((index: number) => this.changeProvince(index))
              Select(this.cityOptions()).id('WeatherCitySelect')
                .selected(this.cities.findIndex((city: WeatherCity) => city.id === this.cityId))
                .value(findWeatherCity(this.cityId).name).font({ size: 14 }).fontColor(INK)
                .backgroundColor(PAGE_BG).borderRadius(12).layoutWeight(1)
                .onSelect((index: number) => { this.cityId = this.cities[index].id; })
            }.width('100%')
            Button('查询天气', { type: ButtonType.Normal }).id('WeatherQueryButton').width('100%').height(44)
              .fontSize(16).fontColor(Color.White).backgroundColor(ACCENT).borderRadius(12).onClick(() => this.query())
          }.width('100%').padding(18).backgroundColor(Color.White).borderRadius(20)

          if (this.view.status === 'loading') {
            Row({ space: 10 }) {
              LoadingProgress().width(24).height(24).color(ACCENT)
              Text(this.view.message).id('WeatherLoading').fontSize(14).fontColor(MUTED).layoutWeight(1)
            }.width('100%').padding(16).backgroundColor('#E6F4F3').borderRadius(16)
          }
          if (this.view.status === 'offline' || this.view.status === 'error') {
            Column({ space: 10 }) {
              Text(this.view.status === 'offline' ? '网络暂时断开' : '天气暂未更新')
                .fontSize(18).fontWeight(FontWeight.Medium).fontColor(INK)
              Text(this.view.message).id('WeatherError').fontSize(14).fontColor(MUTED).textAlign(TextAlign.Center)
              Button('重新尝试', { type: ButtonType.Normal }).id('WeatherRetryButton').fontSize(14)
                .fontColor(ACCENT).backgroundColor('#E2F2F1').borderRadius(12).height(40)
                .onClick(() => { this.controller?.retry(); })
            }.width('100%').padding(22).backgroundColor(Color.White).borderRadius(20)
          }
          if (this.view.cached) {
            Text('正在展示上次成功查询的缓存，可能已过时。联网刷新后可查看最新天气。')
              .id('WeatherCacheNotice').fontSize(13).lineHeight(20).fontColor('#93611E')
              .width('100%').padding(14).backgroundColor('#FFF4DE').borderRadius(14)
          }
          if (this.view.storageWarning) {
            Text(this.view.storageWarning).fontSize(12).fontColor(MUTED).width('100%')
          }
          if (this.view.report) {
            WeatherReportCard({ report: this.view.report, cached: this.view.cached })
            Column({ space: 4 }) {
              Row() {
                Text('未来天气').fontSize(19).fontWeight(FontWeight.Bold).fontColor(INK)
                Blank()
                Text('含今日 · ' + this.view.report.days.length.toString() + ' 天').fontSize(12).fontColor(MUTED)
              }.width('100%').margin({ bottom: 8 })
              ForEach(this.view.report.days, (day: ForecastDay) => {
                WeatherForecastRow({ day: day })
                Divider().color('#EDF1F4')
              }, (day: ForecastDay) => day.date)
            }.id('WeatherForecast').width('100%').padding(18).backgroundColor(Color.White).borderRadius(20)
            Button('刷新当前城市', { type: ButtonType.Normal }).id('WeatherRefreshButton')
              .width('100%').height(44).fontColor(ACCENT).backgroundColor('#E2F2F1').borderRadius(14)
              .enabled(this.view.status !== 'loading').onClick(() => { this.controller?.retry(); })
          }
          Column({ space: 6 }) {
            Text('天气数据由 Open-Meteo 提供 ↗').fontSize(12).fontColor(ACCENT)
              .onClick(() => { this.openSource('https://open-meteo.com/'); })
            Text('当前天气为气象模型估算 · 温度单位 °C\n降水为每日最大概率 · 缺失数据以 — 显示')
              .fontSize(11).lineHeight(18).fontColor(MUTED).textAlign(TextAlign.Center)
            Text('CC BY 4.0 · 已作中文转换与数值取整 ↗').fontSize(11).fontColor(MUTED)
              .onClick(() => { this.openSource('https://creativecommons.org/licenses/by/4.0/'); })
          }.width('100%').padding({ top: 4, bottom: 8 })
        }.width('100%').constraintSize({ maxWidth: 680 }).padding({ left: 20, right: 20, bottom: 24 })
      }.id('WeatherScroll').width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
    }.id('WeatherPage').width('100%').height('100%').backgroundColor(PAGE_BG)
  }
}
