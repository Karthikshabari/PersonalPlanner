import 'backend_connection_profile.dart';

/// Outcome of one explicit cloud lifecycle action.
enum CloudLifecycleOutcome {
  /// The action completed durably.
  completed,

  /// There was nothing to do (for example: no remembered backend to reconnect).
  notApplicable,

  /// Durable state could not be updated; nothing was silently guessed.
  failed,
}

/// Typed result of a lifecycle action, so the UI never has to infer what
/// happened from the absence of an exception.
class CloudLifecycleResult {
  const CloudLifecycleResult({required this.outcome, this.message});

  const CloudLifecycleResult.completed({this.message})
    : outcome = CloudLifecycleOutcome.completed;

  const CloudLifecycleResult.notApplicable({this.message})
    : outcome = CloudLifecycleOutcome.notApplicable;

  const CloudLifecycleResult.failed(String this.message)
    : outcome = CloudLifecycleOutcome.failed;

  final CloudLifecycleOutcome outcome;
  final String? message;

  bool get succeeded => outcome != CloudLifecycleOutcome.failed;
}

/// User-facing copy of the lifecycle actions.
///
/// Kept in the domain layer so the presentation and the tests describe the same
/// consequences. Every sentence here is a promise the implementation keeps:
/// disconnecting never deletes local Planner data, never deletes the Supabase
/// project, and never silently moves Planner data to another project.
const cloudDisconnectTitle = 'Stop using cloud on this device';
const cloudDisconnectExplanation =
    'Stop using this cloud backend on this device. Your Planner data stays on '
    'this device, your Supabase project is not deleted, and you can reconnect '
    'to the same project later.';
const cloudDisconnectConfirmation =
    'Stop using cloud on this device?\n\n'
    '• Local Planner data stays on this device.\n'
    '• Your Supabase project and its cloud data are not deleted.\n'
    '• You are signed out of your Planner account on this device and sync '
    'stops.\n'
    '• You can reconnect later; reconnecting to the same project reuses this '
    'device\'s Planner data.';
const cloudDisconnectFailedMessage =
    'The cloud connection could not be updated on this device, so it was left '
    'unchanged. Local Planner data is safe.';

/// Failure copy for the partial case: sync already stopped and the
/// project-scoped session was already cleared, but the durable "disconnected"
/// flag could not be written.
///
/// The generic [cloudDisconnectFailedMessage] would be untruthful here.
const cloudDisconnectSignedOutStateFailureMessage =
    'You were signed out on this device and sync stopped, but the disconnect '
    'state could not be saved. Local Planner data is safe. Sign in again to '
    'finish disconnecting, or reconnect to keep using this backend.';

/// Failure copy when synchronization was stopped but no session was cleared
/// (no runtime Auth repository was supplied) and the durable "disconnected"
/// flag could not be written.
const cloudDisconnectSyncStoppedStateFailureMessage =
    'Sync stopped, but the disconnect state could not be saved on this device. '
    'Local Planner data is safe. Retry disconnect to finish, or reconnect to '
    'this project.';

const cloudReconnectTitle = 'Reconnect';
const cloudReconnectExplanation =
    'Connect this device to the same user-owned Supabase project again. The '
    'local Planner data of that project is reused; nothing is uploaded until '
    'you sign in and the existing first-sync baseline is confirmed.';

/// True when [profile] is a remembered backend this installation may reconnect
/// to without provisioning anything new.
bool isReconnectableProfile(BackendConnectionProfile? profile) =>
    profile != null &&
    profile.state.isReady &&
    profile.connectionDisabled &&
    profile.projectRef != null;
