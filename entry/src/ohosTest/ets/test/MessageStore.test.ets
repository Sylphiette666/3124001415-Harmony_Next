import { describe, it, expect } from '@ohos/hypium';
import { preferences } from '@kit.ArkData';
import { getTestContext } from './TestContext';
import { MessageStore } from '../../../main/ets/model/MessageStore';

export default function messageStoreTest() {
  describe('MessageBoardStore', () => {
    it('persistsUnicodeAcrossNativeCacheEviction', 0, async () => {
      const context = await getTestContext();
      const name = 'test_board_disk_' + Date.now();
      try {
        const store = new MessageStore(context, name);
        expect((await store.list()).length).assertEqual(0);
        const body = '中文留言 🌱\n"引号" \\ 路径 <script>作为文字保存</script>';
        await store.add({ id: 'unicode', author: '测试同学', body: body });
        await preferences.removePreferencesFromCache(context, name);
        const reopened = new MessageStore(context, name);
        const messages = await reopened.list();
        expect(messages.length).assertEqual(1); expect(messages[0].body).assertEqual(body);
        await reopened.remove('unicode'); await preferences.removePreferencesFromCache(context, name);
        expect((await new MessageStore(context, name).list()).length).assertEqual(0);
      } finally { await preferences.deletePreferences(context, name); }
    });
    it('serializesConcurrentInstancesAndDeduplicatesRetries', 0, async () => {
      const context = await getTestContext();
      const name = 'test_board_queue_' + Date.now();
      try {
        const first = new MessageStore(context, name); const second = new MessageStore(context, name);
        await Promise.all([
          first.add({ id: 'a', author: '测试甲', body: '第一条' }),
          second.add({ id: 'b', author: '测试乙', body: '第二条' }),
          first.add({ id: 'a', author: '测试甲', body: '第一条' })
        ]);
        expect((await first.list()).length).assertEqual(2);
        await second.remove('a'); expect((await first.list()).length).assertEqual(1);
      } finally { await preferences.deletePreferences(context, name); }
    });
    it('rejectsInvalidInputWithoutChangingExistingMessages', 0, async () => {
      const context = await getTestContext();
      const name = 'test_board_validation_' + Date.now();
      try {
        const store = new MessageStore(context, name);
        await store.add({ id: 'valid', author: '测试同学', body: '已有留言' });
        let rejected = false;
        try { await store.add({ id: 'invalid', author: ' ', body: '内容' }); } catch { rejected = true; }
        expect(rejected).assertTrue(); expect((await store.list()).length).assertEqual(1);
      } finally { await preferences.deletePreferences(context, name); }
    });
  });
}
