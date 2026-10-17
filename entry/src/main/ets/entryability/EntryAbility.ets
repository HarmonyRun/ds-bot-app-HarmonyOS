import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0001;
const TAG = 'DSBotEntry';

export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'DS Bot client created');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 系统栏保持透明，具体底色由 ArkUI 当前页面的安全区背景提供。
    // 这样聊天页可衔接白色顶栏/输入栏，首页和设置页则衔接瓷白页面底色。
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: '#172033',
        isStatusBarLightIcon: false,
        navigationBarColor: '#00000000',
        navigationBarContentColor: '#657086',
        isNavigationBarLightIcon: false
      }).catch((error: Error) => {
        hilog.warn(DOMAIN, TAG, `set system bar properties failed: ${error.message}`);
      });
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `get main window failed: ${JSON.stringify(error)}`);
    }

    windowStage.loadContent('pages/Index', (error) => {
      if (error.code !== 0) {
        hilog.error(DOMAIN, TAG, `loadContent failed: ${JSON.stringify(error)}`);
      }
    });
  }
}
