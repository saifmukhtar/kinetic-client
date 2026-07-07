import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import App from './App'
import * as wasm from '@wasm/kinetic_wasm.js'

// Mock the lucide-react icons
vi.mock('lucide-react', () => ({
  ServerCrash: () => <div data-testid="icon-crash" />,
  Loader2: () => <div data-testid="icon-loader" />,
  Globe: () => <div data-testid="icon-globe" />,
}))

// Mock the Wasm module
vi.mock('@wasm/kinetic_wasm.js', () => {
  return {
    default: vi.fn().mockResolvedValue(undefined),
    KineticNode: vi.fn(),
  }
})

describe('Resolver App Component', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    // Reset window location search
    Object.defineProperty(window, 'location', {
      value: { search: '' },
      writable: true,
    })
  })

  it('shows error if no URL is specified', () => {
    window.location.search = ''
    render(<App />)
    
    expect(screen.getByText('Kinetic Domain Not Found')).toBeInTheDocument()
    expect(screen.getByText('No domain specified.')).toBeInTheDocument()
  })

  it('shows loading state initially when URL is provided', () => {
    window.location.search = '?url=http://test.kin'
    
    // Mock the node to never resolve so we stay in loading state
    vi.mocked(wasm.KineticNode).mockImplementation(function() {
      return {
        start: vi.fn(),
        resolve_domain: () => new Promise(() => {}), // never resolves
        fetch_proxy: vi.fn(),
      }
    } as any)

    render(<App />)
    
    expect(screen.getByText('Resolving Domain')).toBeInTheDocument()
    expect(screen.getByText('test.kin')).toBeInTheDocument()
    expect(screen.getByText('Establishing Trustless Tunnel')).toBeInTheDocument()
  })

  it('displays error if domain has no records', async () => {
    window.location.search = '?url=http://missing.kin'
    
    vi.mocked(wasm.KineticNode).mockImplementation(function() {
      return {
        start: vi.fn(),
        resolve_domain: vi.fn().mockResolvedValue(null),
        fetch_proxy: vi.fn(),
      }
    } as any)

    render(<App />)
    
    await waitFor(() => {
      expect(screen.getByText('Kinetic Domain Not Found')).toBeInTheDocument()
      expect(screen.getByText('Domain missing.kin not registered or has no records.')).toBeInTheDocument()
    })
  })
})
