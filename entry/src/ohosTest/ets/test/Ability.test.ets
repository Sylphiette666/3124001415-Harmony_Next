import { describe, it, expect } from '@ohos/hypium';
import { getTestContext } from './TestContext';
import { preferences } from '@kit.ArkData';
import { StudentProfile } from '../../../main/ets/model/CourseData';
import { ProfileStore } from '../../../main/ets/model/ProfileStore';

export default function abilityTest() {
  describe('CourseProfilePersistence', () => {
    it('savesChineseProfileAndReloadsFromDisk', 0, async () => {
      const context = await getTestContext();
      const original = ProfileStore.load(context);
      try {
        const edited = new StudentProfile();
        edited.name = '  测试同学  ';
        edited.studentId = ' 3124001415 ';
        edited.className = '  测试班级  ';
        await ProfileStore.save(context, edited);
        await preferences.removePreferencesFromCache(context, 'course_student');
        const reloaded = ProfileStore.load(context);
        expect(reloaded.name).assertEqual('测试同学');
        expect(reloaded.studentId).assertEqual('3124001415');
        expect(reloaded.className).assertEqual('测试班级');
      } finally {
        // 恢复原有资料，测试数据不会留在首页。
        await ProfileStore.save(context, original);
        await preferences.removePreferencesFromCache(context, 'course_student');
      }
    });
  });
}
