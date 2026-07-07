import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import App from './App';

describe('Popup App Component', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders initial state correctly', () => {
    // Mock sendMessage to do nothing immediately
    vi.mocked(chrome.runtime.sendMessage).mockImplementation(() => {});

    render(<App />);
    
    // Check for title and logo
    expect(screen.getByText('Kinetic Node')).toBeInTheDocument();
    expect(screen.getByText('Decentralised Naming')).toBeInTheDocument();
    expect(screen.getByText('Initializing...')).toBeInTheDocument();
  });

  it('displays Running status when background script responds successfully', async () => {
    // Mock a successful response
    vi.mocked(chrome.runtime.sendMessage).mockImplementation((msg: any, callback: any) => {
      if (msg && msg.type === 'GET_STATUS' && callback) {
        callback({ status: 'Running' });
      }
    });

    render(<App />);

    await waitFor(() => {
      expect(screen.getByText('Running')).toBeInTheDocument();
    });
  });

  it('displays Offline status when background script response is empty', async () => {
    // Mock an empty response
    vi.mocked(chrome.runtime.sendMessage).mockImplementation((msg: any, callback: any) => {
      if (msg && msg.type === 'GET_STATUS' && callback) {
        callback(null);
      }
    });

    render(<App />);

    await waitFor(() => {
      expect(screen.getByText('Offline')).toBeInTheDocument();
    });
  });

  it('displays error if not running in extension context', () => {
    // Temporarily remove chrome.runtime
    const originalRuntime = chrome.runtime;
    // @ts-ignore
    delete chrome.runtime;

    render(<App />);

    expect(screen.getByText('Not running in extension')).toBeInTheDocument();

    // Restore chrome.runtime
    chrome.runtime = originalRuntime;
  });

  it('sends PING_NODE message when Ping Node button is clicked', async () => {
    const user = userEvent.setup();
    render(<App />);

    const pingButton = screen.getByText('Ping Node');
    await user.click(pingButton);

    expect(chrome.runtime.sendMessage).toHaveBeenCalledWith({ type: 'PING_NODE' });
  });
});
