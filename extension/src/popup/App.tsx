import { useEffect, useState } from 'react'
import { Server, Activity, ArrowRightCircle } from 'lucide-react'

export default function App() {
  const [status, setStatus] = useState<string>('Initializing...')
  const [interceptorEnabled, setInterceptorEnabled] = useState<boolean>(true)

  useEffect(() => {
    if (typeof chrome !== 'undefined' && chrome.storage) {
      chrome.storage.local.get(['kinInterceptorEnabled'], (result) => {
        if (result.kinInterceptorEnabled !== undefined) {
          setInterceptorEnabled(result.kinInterceptorEnabled as boolean)
        }
      })
    }

    // Ping the background script to get status
    if (typeof chrome !== 'undefined' && chrome.runtime) {
      chrome.runtime.sendMessage({ type: 'GET_STATUS' }, (response: any) => {
        if (response) {
          setStatus(response.status)
        } else {
          setStatus('Offline')
        }
      })
    } else {
      setStatus('Not running in extension')
    }
  }, [])

  const isRunning = status === 'Running'

  const toggleInterceptor = () => {
    const newValue = !interceptorEnabled;
    setInterceptorEnabled(newValue);
    if (typeof chrome !== 'undefined' && chrome.storage) {
      chrome.storage.local.set({ kinInterceptorEnabled: newValue });
    }
  }

  return (
    <div className="flex flex-col items-center w-[320px] bg-[#0a0a0f] p-5 font-sans relative overflow-hidden text-slate-200 shadow-xl border border-white/5">
      
      {/* Sleek dark mode ambient glows */}
      <div className="absolute top-[-40px] left-[-20px] w-40 h-40 bg-blue-500/20 rounded-full blur-3xl pointer-events-none"></div>
      <div className="absolute bottom-[-40px] right-[-20px] w-40 h-40 bg-purple-500/20 rounded-full blur-3xl pointer-events-none"></div>

      <div className="z-10 flex flex-col items-center w-full">
        <div className="relative mb-4 mt-2 flex items-center justify-center">
          {/* Logo container (no white box) */}
          <div className="relative flex items-center justify-center">
            <img 
              src="/kinetic-logo.svg" 
              alt="Kinetic Logo" 
              className={`w-16 h-16 object-contain z-10 ${isRunning ? 'drop-shadow-[0_0_15px_rgba(59,130,246,0.6)]' : 'opacity-50 grayscale'}`} 
            />
            {isRunning && (
              <div className="absolute inset-0 rounded-full border border-blue-400/30 animate-ping opacity-50 z-0 scale-125"></div>
            )}
          </div>
        </div>
        
        <div className="text-center space-y-0.5 mb-5">
          <h1 className="text-xl font-bold text-white tracking-tight">
            Kinetic Node
          </h1>
          <p className="text-slate-400 text-[10px] font-semibold uppercase tracking-widest">
            Decentralised Naming
          </p>
        </div>

        {/* Status Card */}
        <div className="w-full bg-white/[0.03] hover:bg-white/[0.05] transition-colors border border-white/10 rounded-xl p-3.5 shadow-lg backdrop-blur-md">
          <div className="flex items-center justify-between mb-1">
            <div className="flex items-center space-x-1.5 text-slate-400">
              <Activity className="w-3.5 h-3.5 text-blue-400" />
              <h3 className="text-[10px] uppercase font-bold tracking-wider text-slate-300">Status</h3>
            </div>
            <span className="relative flex h-2.5 w-2.5">
              {isRunning && <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>}
              <span className={`relative inline-flex rounded-full h-2.5 w-2.5 ${isRunning ? 'bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.8)]' : (status === 'Initializing...' ? 'bg-amber-400' : 'bg-slate-500')}`}></span>
            </span>
          </div>
          <div className="font-medium text-white text-sm tracking-wide">
            {status}
          </div>
        </div>

        {/* Interceptor Toggle */}
        <div className="w-full bg-white/[0.03] hover:bg-white/[0.05] transition-colors border border-white/10 rounded-xl p-3.5 shadow-lg backdrop-blur-md mt-2.5">
          <div className="flex items-center justify-between">
            <div className="flex flex-col">
              <span className="font-medium text-white text-sm">.kin Interceptor</span>
              <span className="text-[10px] text-slate-400 mt-0.5">Trustless P2P resolution</span>
            </div>
            <button 
              onClick={toggleInterceptor}
              className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors ${interceptorEnabled ? 'bg-blue-600 shadow-[0_0_10px_rgba(37,99,235,0.4)]' : 'bg-white/10 border border-white/20'}`}
            >
              <span className={`inline-block h-3.5 w-3.5 transform rounded-full bg-white shadow-sm transition-transform ${interceptorEnabled ? 'translate-x-[18px]' : 'translate-x-1'}`} />
            </button>
          </div>
        </div>
      </div>
      
      {/* Ping Button */}
      <button 
        className="z-10 mt-5 w-full group relative flex items-center justify-center gap-2 py-2.5 bg-white/5 hover:bg-white/10 border border-white/10 hover:border-white/20 text-white rounded-xl font-medium shadow-md transition-all active:scale-[0.98]"
        onClick={() => {
          if (typeof chrome !== 'undefined' && chrome.runtime) {
            chrome.runtime.sendMessage({ type: 'PING_NODE' });
          }
        }}
      >
        <Server className="w-4 h-4 text-blue-400 group-hover:text-blue-300 transition-colors" />
        <span className="text-sm tracking-wide">Ping Node</span>
        <ArrowRightCircle className="w-4 h-4 text-white/30 group-hover:text-white/70 transition-colors absolute right-4" />
      </button>
    </div>
  )
}
