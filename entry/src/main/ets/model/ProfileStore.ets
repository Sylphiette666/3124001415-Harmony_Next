import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { StudentProfile } from './CourseData';

export class ProfileStore {
  static load(context: common.Context): StudentProfile {
    try {
      const store = preferences.getPreferencesSync(context, { name: 'course_student' });
      const profile = new StudentProfile();
      profile.name = store.getSync('name', '') as string;
      profile.studentId = store.getSync('studentId', '3124001415') as string;
      profile.className = store.getSync('className', '') as string;
      return profile;
    } catch (error) {
      throw new Error('Unable to load student profile: ' + JSON.stringify(error));
    }
  }
  static async save(context: common.Context, profile: StudentProfile): Promise<void> {
    try {
      const store = preferences.getPreferencesSync(context, { name: 'course_student' });
      store.putSync('name', profile.name.trim());
      store.putSync('studentId', profile.studentId.trim());
      store.putSync('className', profile.className.trim());
      await store.flush();
    } catch (error) {
      throw new Error('Unable to save student profile: ' + JSON.stringify(error));
    }
  }
}
