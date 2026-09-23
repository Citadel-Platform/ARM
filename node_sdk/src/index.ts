import { ArmNode, type ArmNodeOptions } from './arm.js';

export {
  type ArmCapture,
  ArmNode,
  type ArmNodeOptions,
  armNodeVersion,
  type ArmSeverity,
  type CaptureOptions,
  type RequestContext,
} from './arm.js';
export {
  armErrorHandler,
  armFastify,
  armNextOnRequestError,
  armRequestHandler,
  type RequestHookOptions,
} from './frameworks.js';

/** Starts ARM in this process and returns it. */
export function init(options: ArmNodeOptions): ArmNode {
  return new ArmNode(options);
}
