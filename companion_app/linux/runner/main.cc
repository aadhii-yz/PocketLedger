#include <cstdlib>
#include "my_application.h"

int main(int argc, char** argv) {
  // WPE WebKit's EGL zero-copy texture sharing has compositing issues with
  // Flutter's GL renderer on Intel i915 and similar hardware. Software
  // rendering avoids this without meaningfully impacting this companion app.
  setenv("LIBGL_ALWAYS_SOFTWARE", "true", 0);  // 0 = don't override if user set it
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
