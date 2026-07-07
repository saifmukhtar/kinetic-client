import '@testing-library/jest-dom';
import { vi } from 'vitest';

// Mock chrome extension APIs globally
(globalThis as any).chrome = {
  runtime: {
    sendMessage: vi.fn(),
    getURL: vi.fn((path: string) => `chrome-extension://mock-id/${path}`),
    onMessage: {
      addListener: vi.fn(),
      removeListener: vi.fn(),
      hasListener: vi.fn(),
    },
    onInstalled: {
      addListener: vi.fn(),
    },
    onStartup: {
      addListener: vi.fn(),
    },
  },
  offscreen: {
    createDocument: vi.fn(),
    Reason: {
      LOCAL_STORAGE: 'LOCAL_STORAGE',
      DOM_PARSER: 'DOM_PARSER',
    },
  },
} as unknown as typeof chrome;
