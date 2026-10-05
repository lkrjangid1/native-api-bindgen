/** Runs the self-test suite for the current platform. */
import { Platform } from 'react-native';

import { selfTests as android } from './selfTestsAndroid';
import { selfTests as ios } from './selfTestsIos';

export type { TestResult } from './testResult';

export const selfTests = Platform.OS === 'ios' ? ios : android;
