import { useEffect, useState, useRef } from 'react'
import { ServerCrash, Loader2, Globe } from 'lucide-react'
import init, { KineticNode } from '../../public/wasm/kinetic_wasm.js'

export default function App() {
  const [error, setError] = useState<string | null>(null)
  const [targetUrl, setTargetUrl] = useState<string>('')
  const [htmlContent, setHtmlContent] = useState<string | null>(null)
  const iframeRef = useRef<HTMLIFrameElement>(null)
  
  useEffect(() => {
    // Parse ?url=... from the window location
    const params = new URLSearchParams(window.location.search);
    const urlParam = params.get('url');
    if (!urlParam) {
      setError("No domain specified.");
      return;
    }
    
    let targetHostname = '';
    let urlObj: URL;
    try {
      urlObj = new URL(urlParam);
      targetHostname = urlObj.hostname;
      setTargetUrl(targetHostname);
    } catch (e) {
      targetHostname = urlParam;
      setTargetUrl(urlParam);
      // fallback mock url for pathname parsing
      urlObj = new URL(`http://${urlParam}`); 
    }
    
    // Initialize Wasm node, look up domain, and fetch content over P2P
    const resolveDomain = async () => {
      try {
        await init('/wasm/kinetic_wasm_bg.wasm');
        const node: any = new KineticNode((type: string, msg: string) => {
          console.log(`[WASM EVENT] ${type}: ${msg}`);
        });
        node.start();

        // 1. Resolve domain
        const domainRecord = await node.resolve_domain(targetHostname);
        if (!domainRecord || !domainRecord.records || !domainRecord.records["@"]) {
          setError(`Domain ${targetHostname} not registered or has no records.`);
          return;
        }

        // 2. Find a PeerId record
        const peerRecord = domainRecord.records["@"].find((r: any) => r.type === "PeerId");
        if (!peerRecord) {
          setError(`Domain ${targetHostname} does not point to a Kinetic Host.`);
          return;
        }

        const peerId = peerRecord.value;

        // 3. Fetch from proxy
        const path = urlObj.pathname + urlObj.search;
        const responseBytes = await node.fetch_proxy(peerId, path);
        
        // 4. Decode HTML
        const decoder = new TextDecoder();
        const html = decoder.decode(responseBytes);
        setHtmlContent(html);

      } catch (err: any) {
        console.error("Resolution failed:", err);
        setError(err.toString());
      }
    };

    resolveDomain();

  }, []);

  useEffect(() => {
    if (htmlContent && iframeRef.current) {
      const iframeDoc = iframeRef.current.contentWindow?.document;
      if (iframeDoc) {
        iframeDoc.open();
        iframeDoc.write(htmlContent);
        iframeDoc.close();
      }
    }
  }, [htmlContent]);

  if (error) {
    return (
      <div className="flex flex-col items-center justify-center min-h-screen bg-slate-50 p-6 font-sans">
        <ServerCrash className="w-16 h-16 text-red-400 mb-4" />
        <h1 className="text-2xl font-bold text-slate-800 mb-2">Kinetic Domain Not Found</h1>
        <p className="text-slate-500 text-center max-w-md">
          {error}
        </p>
      </div>
    )
  }

  if (htmlContent) {
    return (
      <iframe
        ref={iframeRef}
        title="Decentralized Content"
        style={{ width: '100%', height: '100vh', border: 'none', background: 'white' }}
        sandbox="allow-scripts allow-same-origin"
      />
    );
  }

  return (
    <div className="flex flex-col items-center justify-center min-h-screen bg-slate-50 p-6 font-sans overflow-hidden relative">
      <div className="absolute top-[-50px] left-[-50px] w-64 h-64 bg-blue-100 rounded-full mix-blend-multiply filter blur-3xl opacity-70 animate-pulse"></div>
      <div className="absolute bottom-[-50px] right-[-50px] w-64 h-64 bg-indigo-100 rounded-full mix-blend-multiply filter blur-3xl opacity-70 animate-pulse" style={{ animationDelay: '1s' }}></div>

      <div className="relative mb-8 z-10">
        <div className="w-24 h-24 rounded-full bg-white shadow-xl flex items-center justify-center">
          <Globe className="w-12 h-12 text-blue-500 animate-pulse" />
        </div>
        <div className="absolute inset-0 rounded-full border-[3px] border-blue-400 border-t-transparent animate-spin"></div>
      </div>
      
      <h1 className="text-3xl font-bold text-slate-800 mb-3 tracking-tight z-10">
        Resolving Domain
      </h1>
      <p className="text-slate-500 text-center max-w-md font-mono text-sm bg-white/60 px-4 py-2 rounded-full shadow-sm z-10">
        {targetUrl || 'Connecting to Mesh...'}
      </p>
      
      <div className="mt-10 flex items-center gap-3 text-indigo-500 text-xs uppercase tracking-[0.2em] font-bold z-10 bg-indigo-50/50 px-5 py-2.5 rounded-full border border-indigo-100/50">
        <Loader2 className="w-4 h-4 animate-spin" />
        <span>Establishing Trustless Tunnel</span>
      </div>
    </div>
  )
}
