import { describe, it, expect } from '@ohos/hypium';
import { getTestContext } from './TestContext';
import { preferences } from '@kit.ArkData';
import { BusinessCard, CARD_GROUPS, copyCard, filterCards, validateCard } from '../../../main/ets/model/BusinessCard';
import { CardStore } from '../../../main/ets/model/CardStore';

function makeCard(name: string = '测试同学'): BusinessCard {
  const card = new BusinessCard();
  card.name = name;
  card.phone = '13800138000';
  card.organization = '鸿蒙课程';
  card.group = '同学';
  return card;
}

async function assertRejected(operation: () => Promise<void>): Promise<void> {
  let rejected = false;
  try {
    await operation();
  } catch (error) {
    rejected = true;
  }
  expect(rejected).assertTrue();
}

function assertLoadRejected(store: CardStore): void {
  let rejected = false;
  try {
    store.load();
  } catch (error) {
    rejected = true;
  }
  expect(rejected).assertTrue();
}

export default function cardStoreTest() {
  describe('BusinessCardLocalManagement', () => {
    it('createsUpdatesAndDeletesWithDiskReload', 0, async () => {
      const context = await getTestContext();
      const storageName = 'test_cards_crud_' + Date.now();
      const store = new CardStore(context, storageName);
      try {
        expect(store.load().length).assertEqual(0);
        const draft = makeCard('  张三  ');
        draft.phone = ' 13800138000 ';
        draft.email = ' student@example.com ';
        draft.note = ' 同班同学，周五一起交流 ArkTS。 ';
        const created = await store.save(draft);
        expect(created.id.length > 0).assertTrue();
        expect(draft.id).assertEqual('');
        expect(created.name).assertEqual('张三');
        expect(created.phone).assertEqual('13800138000');
        expect(created.createdAt > 0).assertTrue();
        await preferences.removePreferencesFromCache(context, storageName);
        const freshStore = new CardStore(context, storageName);
        const loaded = freshStore.load();
        expect(loaded.length).assertEqual(1);
        expect(loaded[0].id).assertEqual(created.id);
        expect(loaded[0].email).assertEqual('student@example.com');
        expect(loaded[0].note).assertEqual('同班同学，周五一起交流 ArkTS。');
        loaded[0].name = '只修改外部副本';
        expect(freshStore.load()[0].name).assertEqual('张三');
        const edited = copyCard(created);
        edited.name = '张三同学';
        edited.address = '教学楼 301';
        const updated = await freshStore.save(edited);
        expect(updated.id).assertEqual(created.id);
        expect(updated.createdAt).assertEqual(created.createdAt);
        expect(updated.updatedAt > created.updatedAt).assertTrue();
        await preferences.removePreferencesFromCache(context, storageName);
        expect(store.load()[0].name).assertEqual('张三同学');
        expect(store.load()[0].address).assertEqual('教学楼 301');
        await store.remove(created.id);
        await preferences.removePreferencesFromCache(context, storageName);
        expect(new CardStore(context, storageName).load().length).assertEqual(0);
      } finally {
        await preferences.deletePreferences(context, storageName);
      }
    });

    it('favoritesAndSearchCombineWithGroupsAndConcurrentWrites', 0, async () => {
      const context = await getTestContext();
      const storageName = 'test_cards_search_' + Date.now();
      const store = new CardStore(context, storageName);
      try {
        const teacher = makeCard('李老师');
        teacher.group = '老师';
        teacher.organization = 'OpenHarmony 实验室';
        teacher.title = '课程导师';
        teacher.email = 'Teacher@Example.com';
        teacher.phone = '+86 (10) 1234-5678';
        const student = makeCard('王同学');
        student.note = '备注不会误入姓名和联系方式搜索';
        const worker = makeCard('陈工程师');
        worker.group = '工作';
        worker.phone = '13900139000';
        const otherInstance = new CardStore(context, storageName);
        const saved = await Promise.all([store.save(teacher), otherInstance.save(student), store.save(worker)]);
        expect(store.load().length).assertEqual(3);
        const favorite = await store.toggleFavorite(saved[0].id);
        expect(favorite.favorite).assertTrue();
        await preferences.removePreferencesFromCache(context, storageName);
        const cards = otherInstance.load();
        expect(filterCards(cards, '')[0].id).assertEqual(saved[0].id);
        expect(filterCards(cards, ' openharmony ')[0].id).assertEqual(saved[0].id);
        expect(filterCards(cards, '课程导师')[0].id).assertEqual(saved[0].id);
        expect(filterCards(cards, 'TEACHER@EXAMPLE.COM')[0].id).assertEqual(saved[0].id);
        expect(filterCards(cards, '1234-5678')[0].id).assertEqual(saved[0].id);
        expect(filterCards(cards, '王同学')[0].id).assertEqual(saved[1].id);
        expect(filterCards(cards, '备注不会').length).assertEqual(0);
        expect(filterCards(cards, '', '老师', true).length).assertEqual(1);
        expect(filterCards(cards, '', '同学', true).length).assertEqual(0);
        expect(filterCards(cards, '陈', '工作').length).assertEqual(1);
        const resultCopy = filterCards(cards, '李');
        resultCopy[0].name = '外部变动';
        expect(cards.find((card: BusinessCard) => card.id === saved[0].id)?.name).assertEqual('李老师');
        expect((await store.toggleFavorite(saved[0].id)).favorite).assertFalse();
        await preferences.removePreferencesFromCache(context, storageName);
        expect(filterCards(store.load(), '', '全部', true).length).assertEqual(0);
        expect(filterCards(store.load(), '')[0].id).assertEqual(saved[0].id);
      } finally {
        await preferences.deletePreferences(context, storageName);
      }
    });

    it('rejectsInvalidInputAndMissingIdsWithoutChangingSavedCards', 0, async () => {
      const context = await getTestContext();
      const storageName = 'test_cards_validation_' + Date.now();
      const store = new CardStore(context, storageName);
      try {
        const existing = await store.save(makeCard());
        const invalid = makeCard('  ');
        expect(validateCard(invalid).length > 0).assertTrue();
        await assertRejected(async () => { await store.save(invalid); });
        invalid.name = '联系信息测试';
        invalid.phone = '';
        expect(validateCard(invalid).length > 0).assertTrue();
        invalid.email = 'wrong-address';
        expect(validateCard(invalid).length > 0).assertTrue();
        invalid.email = 'valid@example.com';
        expect(validateCard(invalid)).assertEqual('');
        invalid.phone = '123';
        expect(validateCard(invalid).length > 0).assertTrue();
        invalid.phone = '123abc456789';
        expect(validateCard(invalid).length > 0).assertTrue();
        invalid.phone = '';
        invalid.group = '未知分组';
        expect(validateCard(invalid).length > 0).assertTrue();
        invalid.group = CARD_GROUPS[0];
        invalid.name = '长'.repeat(41);
        expect(validateCard(invalid).length > 0).assertTrue();
        invalid.name = '正常姓名';
        invalid.note = '长'.repeat(501);
        await assertRejected(async () => { await store.save(invalid); });
        const missing = makeCard();
        missing.id = 'already-deleted';
        await assertRejected(async () => { await store.save(missing); });
        await assertRejected(async () => { await store.remove('missing'); });
        await assertRejected(async () => { await store.toggleFavorite('missing'); });
        await preferences.removePreferencesFromCache(context, storageName);
        expect(store.load().length).assertEqual(1);
        expect(store.load()[0].id).assertEqual(existing.id);
        // 前一次失败不影响后续正常写入。
        await store.save(makeCard('继续保存'));
        expect(store.load().length).assertEqual(2);
      } finally {
        await preferences.deletePreferences(context, storageName);
      }
    });

    it('preservesCorruptJsonAndRejectsMalformedOrIncompleteSchema', 0, async () => {
      const context = await getTestContext();
      const storageName = 'test_cards_corrupt_' + Date.now();
      const store = new CardStore(context, storageName);
      try {
        const raw = preferences.getPreferencesSync(context, { name: storageName });
        raw.putSync('cards_manifest', '{"version":1,"chunks":1}');
        raw.putSync('cards_chunk_0', '{broken-json');
        await raw.flush();
        assertLoadRejected(store);
        await assertRejected(async () => { await store.save(makeCard()); });
        await assertRejected(async () => { await store.remove('missing'); });
        await assertRejected(async () => { await store.toggleFavorite('missing'); });
        await preferences.removePreferencesFromCache(context, storageName);
        const disk = preferences.getPreferencesSync(context, { name: storageName });
        expect(disk.getSync('cards_chunk_0', '') as string).assertEqual('{broken-json');
        expect(disk.getSync('cards_manifest', '') as string).assertEqual('{"version":1,"chunks":1}');
        const malformedDocuments: string[] = ['null', '[]', '{"version":2,"cards":[]}',
          '{"version":1,"cards":{}}', '{"version":1,"cards":[null]}',
          '{"version":1,"cards":[{"id":"bad","name":"缺失字段"}]}'];
        for (let index = 0; index < malformedDocuments.length; index++) {
          disk.putSync('cards_chunk_0', malformedDocuments[index]);
          await disk.flush();
          assertLoadRejected(store);
          await assertRejected(async () => { await store.save(makeCard()); });
          expect(disk.getSync('cards_chunk_0', '') as string).assertEqual(malformedDocuments[index]);
        }
        const duplicate = makeCard();
        duplicate.id = 'duplicate-id';
        duplicate.createdAt = Date.now();
        duplicate.updatedAt = duplicate.createdAt;
        const wrongFavorite = JSON.stringify(duplicate).replace('"favorite":false', '"favorite":"false"');
        disk.putSync('cards_chunk_0', '{"version":1,"cards":[' + wrongFavorite + ']}');
        await disk.flush();
        assertLoadRejected(store);
        const duplicateJson = '{"version":1,"cards":[' + JSON.stringify(duplicate) + ',' +
          JSON.stringify(duplicate) + ']}';
        disk.putSync('cards_chunk_0', duplicateJson);
        await disk.flush();
        assertLoadRejected(store);
        disk.putSync('cards_manifest', '{"version":1,"chunks":2}');
        await disk.flush();
        assertLoadRejected(store);
        disk.deleteSync('cards_manifest');
        await disk.flush();
        assertLoadRejected(store);
        await assertRejected(async () => { await store.save(makeCard()); });
        expect(disk.getSync('cards_chunk_0', '') as string).assertEqual(duplicateJson);
      } finally {
        await preferences.deletePreferences(context, storageName);
      }
    });

    it('roundTripsMoreThanOnePreferencesStringOfChineseCards', 0, async () => {
      const context = await getTestContext();
      const storageName = 'test_cards_chunks_' + Date.now();
      const store = new CardStore(context, storageName);
      try {
        for (let index = 0; index < 14; index++) {
          const card = makeCard('分块测试 ' + index);
          card.note = '中文📇'.repeat(125);
          await store.save(card);
        }
        await preferences.removePreferencesFromCache(context, storageName);
        const persisted = new CardStore(context, storageName).load();
        expect(persisted.length).assertEqual(14);
        expect(JSON.stringify(persisted).length > 8192).assertTrue();
        for (let index = 0; index < persisted.length; index++) {
          expect(persisted[index].note).assertEqual('中文📇'.repeat(125));
        }
        for (let index = 0; index < persisted.length; index++) {
          await store.remove(persisted[index].id);
        }
        await preferences.removePreferencesFromCache(context, storageName);
        expect(store.load().length).assertEqual(0);
        const remainingKeys = Object.keys(preferences.getPreferencesSync(context, { name: storageName })
          .getAllSync()).filter((key: string) => key.indexOf('cards_chunk_') === 0);
        expect(remainingKeys.length).assertEqual(1);
      } finally {
        await preferences.deletePreferences(context, storageName);
      }
    });
  });
}
