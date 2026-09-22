#include "my_application.h"

int main(int argc, char** argv) {
  bool reminder_worker = false;
  for (int i = 1; i < argc; ++i) {
    if (g_strcmp0(argv[i], "--planner-reminder-worker") == 0) {
      reminder_worker = true;
      break;
    }
  }
  g_autoptr(MyApplication) app = my_application_new(reminder_worker);
  return g_application_run(G_APPLICATION(app), argc, argv);
}
