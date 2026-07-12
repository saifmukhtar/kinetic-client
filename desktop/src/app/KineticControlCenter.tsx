import { useEffect, useMemo, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { KineticApiError, getErrorMessage } from '../lib/error';
import {
  Activity,
  AlertTriangle,
  ArrowRight,
  CheckCircle2,
  CircleDot,
  Clock3,
  Cpu,
  Database,
  FileClock,
  Globe2,
  HardDrive,
  KeyRound,
  Loader2,
  Network,
  Plus,
  RefreshCw,
  Rocket,
  Save,
  Search,
  ServerCog,
  ShieldCheck,
  SlidersHorizontal,
  Sparkles,
  UploadCloud,
  WifiOff,
} from 'lucide-react';

type DaemonState = 'checking' | 'online' | 'offline';

type NetworkStatus = {
  status?: string;
  peers?: number;
  dht_size?: number;
  uptime?: string;
  drand_pulse?: number;
  nat_status?: string;
  [key: string]: unknown;
};

type DnsRecord = {
  id: string;
  name: string;
  type: string;
  value: string;
};

type VdfStatus = {
  status?: string;
  iterations?: number;
  progress?: number;
  error?: string | null;
};

type ResolveResult = {
  state: 'idle' | 'loading' | 'success' | 'error';
  message?: string;
  data?: Record<string, unknown>;
};

type InstallProfile = 'complete' | 'minimal';

const API_BASE = 'http://127.0.0.1:16002';
const recordTypes = ['A', 'AAAA', 'TXT', 'CNAME', 'PeerId', 'KID'];

function classNames(...classes: Array<string | false | null | undefined>) {
  return classes.filter(Boolean).join(' ');
}

function normalizeDisplayName(name: string) {
  return name.endsWith('.') ? name.slice(0, -1) : name;
}

function createRecord(record?: Partial<DnsRecord>): DnsRecord {
  return {
    id: crypto.randomUUID(),
    name: record?.name ?? '@',
    type: record?.type ?? 'A',
    value: record?.value ?? '',
  };
}



async function readJson<T>(path: string, init?: RequestInit): Promise<T> {
  // Get API token from backend
  const token = await invoke<string>('get_api_token').catch(() => null);
  
  const headers = new Headers(init?.headers);
  if (token) {
    headers.set('Authorization', `Bearer ${token}`);
  }

  const response = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers,
  });

  const text = await response.text();
  const body = text ? JSON.parse(text) : null;
  if (!response.ok) {
    if (response.status === 401 || response.status === 403) {
      throw new KineticApiError('Daemon authentication failed. The local daemon is rejecting the Desktop API token or the token is missing.', String(response.status));
    }

    if (body && typeof body === 'object' && 'code' in body && 'message' in body) {
      const b = body as { code: string; message: string; detail?: string };
      throw new KineticApiError(b.message, b.code, b.detail);
    }
    const errorMessage =
      body && typeof body === 'object' && 'error' in body
        ? String((body as { error: unknown }).error)
        : `Request failed with ${response.status}`;
    throw new KineticApiError(errorMessage);
  }
  return body as T;
}

function flattenZone(zone: unknown): DnsRecord[] {
  if (!zone || typeof zone !== 'object' || !('records' in zone)) {
    return [];
  }

  const zoneRecords = (zone as { records?: Record<string, unknown> }).records;
  if (!zoneRecords) {
    return [];
  }

  return Object.entries(zoneRecords).flatMap(([label, value]) => {
    if (!Array.isArray(value)) {
      return [];
    }

    return value.map((entry) => {
      const record = entry as { type?: unknown; value?: unknown };
      return createRecord({
        name: label,
        type: typeof record.type === 'string' ? record.type : 'TXT',
        value: typeof record.value === 'string' ? record.value : '',
      });
    });
  });
}

function StatusPill({
  state,
  label,
}: {
  state: 'good' | 'warn' | 'bad' | 'neutral';
  label: string;
}) {
  const styles = {
    good: 'border-lime-400/35 bg-lime-400/10 text-lime-200',
    warn: 'border-orange-400/35 bg-orange-400/10 text-orange-200',
    bad: 'border-rose-500/30 bg-rose-500/10 text-rose-300',
    neutral: 'border-zinc-700 bg-zinc-900 text-zinc-300',
  };

  return (
    <span className={classNames('inline-flex items-center gap-2 rounded-md border px-2.5 py-1 text-xs font-medium', styles[state])}>
      <span className={classNames('h-1.5 w-1.5 rounded-full', state === 'good' && 'bg-lime-300', state === 'warn' && 'bg-orange-300', state === 'bad' && 'bg-rose-300', state === 'neutral' && 'bg-zinc-400')} />
      {label}
    </span>
  );
}

function SectionHeader({
  eyebrow,
  title,
  action,
}: {
  eyebrow: string;
  title: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex items-start justify-between gap-4">
      <div>
        <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-orange-200/80">{eyebrow}</div>
        <h2 className="mt-1 text-xl font-semibold text-slate-50">{title}</h2>
      </div>
      {action}
    </div>
  );
}

function Panel({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <section className={classNames('rounded-lg border border-white/10 bg-[#11131a]/78 shadow-[0_20px_60px_rgba(0,0,0,0.22)] backdrop-blur-xl', className)}>
      {children}
    </section>
  );
}

function Metric({
  icon: Icon,
  label,
  value,
  note,
}: {
  icon: React.ElementType;
  label: string;
  value: string;
  note: string;
}) {
  return (
    <div className="min-w-0 rounded-md border border-white/10 bg-[#191b24]/80 p-4">
      <div className="flex items-center justify-between gap-3">
        <span className="text-xs font-medium uppercase tracking-[0.14em] text-slate-500">{label}</span>
        <Icon size={18} className="shrink-0 text-lime-300" />
      </div>
      <div className="mt-4 break-words text-2xl font-semibold text-slate-50">{value}</div>
      <div className="mt-1 text-xs leading-5 text-zinc-500">{note}</div>
    </div>
  );
}

function JsonPreview({ data }: { data: Record<string, unknown> }) {
  return (
    <pre className="max-h-64 overflow-auto rounded-md border border-white/10 bg-black/35 p-3 text-xs leading-relaxed text-slate-300">
      {JSON.stringify(data, null, 2)}
    </pre>
  );
}

export function KineticControlCenter() {
  const [activeSection, setActiveSection] = useState<'control' | 'identity' | 'names' | 'resolver' | 'engine' | 'preferences' | 'mempool'>('control');
  const [daemonState, setDaemonState] = useState<DaemonState>('checking');
  const [networkStatus, setNetworkStatus] = useState<NetworkStatus | null>(null);
  const [ownedNames, setOwnedNames] = useState<string[]>([]);
  const [mempoolData, setMempoolData] = useState<{ active_tasks: Record<string, VdfStatus>; queue: Array<{ request: { hashcash_nonce: number; challenge_hash: number[] }, timestamp: { secs_since_epoch: number } }> } | null>(null);
  const [selectedName, setSelectedName] = useState<string | null>(null);
  const [records, setRecords] = useState<DnsRecord[]>([]);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [nameMessage, setNameMessage] = useState('');
  const [resolveName, setResolveName] = useState('saif.kin');
  const [resolveResult, setResolveResult] = useState<ResolveResult>({ state: 'idle' });
  const [registerName, setRegisterName] = useState('');
  const [vdfTaskId, setVdfTaskId] = useState<string | null>(null);
  const [vdfStatus, setVdfStatus] = useState<VdfStatus | null>(null);
  const [selectedProfile, setSelectedProfile] = useState<InstallProfile>('complete');
  const [cleanMode, setCleanMode] = useState(false);
  const [isInstalling, setIsInstalling] = useState(false);
  const [installMessage, setInstallMessage] = useState('');
  const [themeMode, setThemeMode] = useState<'adaptive' | 'dark' | 'light'>('adaptive');
  const [launchOnStartup, setLaunchOnStartup] = useState(true);

  const [seedPhrase, setSeedPhrase] = useState('');
  const [backupChecked, setBackupChecked] = useState(false);
  const [restorePhrase, setRestorePhrase] = useState('');
  const [identityMessage, setIdentityMessage] = useState('');

  const handleGenerateSeed = async () => {
    try {
      setIdentityMessage('');
      const phrase = await invoke<string>('generate_seed');
      setSeedPhrase(phrase);
      setBackupChecked(false);
    } catch (error) {
      setIdentityMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const handleSaveIdentity = async (phrase: string) => {
    try {
      setIdentityMessage('Saving identity and restarting daemon...');
      await invoke<void>('save_identity', { phrase });
      setIdentityMessage('Identity saved successfully! Daemon restarted.');
      setSeedPhrase('');
      setRestorePhrase('');
      await refresh();
    } catch (error) {
      setIdentityMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const refresh = async () => {
    setIsRefreshing(true);
    try {
      const [status, names, mempool] = await Promise.all([
        readJson<NetworkStatus>('/network-status'),
        readJson<string[]>('/owned-names'),
        readJson<any>('/mempool').catch(() => null),
      ]);
      setDaemonState('online');
      setNetworkStatus(status);
      setOwnedNames(names);
      setMempoolData(mempool);
      setSelectedName((current) => current ?? names[0] ?? null);
    } catch {
      setDaemonState('offline');
      setNetworkStatus(null);
      setOwnedNames([]);
    } finally {
      setIsRefreshing(false);
    }
  };

  useEffect(() => {
    refresh();
    const interval = window.setInterval(refresh, 7000);
    return () => window.clearInterval(interval);
  }, []);

  useEffect(() => {
    const loadZone = async () => {
      if (!selectedName) {
        setRecords([]);
        return;
      }

      try {
        const zone = await readJson<unknown>(`/zone/${encodeURIComponent(selectedName)}`);
        setRecords(flattenZone(zone));
      } catch {
        setRecords([]);
      }
    };

    loadZone();
  }, [selectedName]);

  useEffect(() => {
    if (!vdfTaskId) {
      return undefined;
    }

    const eventSource = new EventSource(`${API_BASE}/vdf/events/${vdfTaskId}`);

    eventSource.onmessage = (event) => {
      try {
        const status = JSON.parse(event.data) as VdfStatus;
        setVdfStatus(status);
        if ((status.progress ?? 0) >= 100 || status.error) {
          eventSource.close();
          readJson<Record<string, unknown>>(`/vdf/status/${vdfTaskId}`, { method: 'DELETE' }).catch(() => undefined);
          if ((status.progress ?? 0) >= 100) {
            setVdfTaskId(null);
            setRegisterName('');
            refresh();
          }
        }
      } catch {
        // Ignore JSON parse errors
      }
    };

    eventSource.onerror = () => {
      setVdfStatus({ status: 'Disconnected', progress: 0, error: 'Lost connection to daemon while streaming VDF task.' });
      eventSource.close();
    };

    return () => eventSource.close();
  }, [vdfTaskId]);

  const health = useMemo(() => {
    if (daemonState === 'checking') {
      return { label: 'Checking daemon', state: 'neutral' as const, icon: Loader2 };
    }
    if (daemonState === 'offline') {
      return { label: 'Daemon offline', state: 'bad' as const, icon: WifiOff };
    }
    const statusText = String(networkStatus?.status ?? 'Online');
    const isError = statusText.toLowerCase().includes('error');
    return {
      label: isError ? 'Network degraded' : 'Local engine online',
      state: isError ? ('warn' as const) : ('good' as const),
      icon: isError ? AlertTriangle : CheckCircle2,
    };
  }, [daemonState, networkStatus]);

  const saveZone = async () => {
    if (!selectedName) {
      return;
    }

    const zone = records.reduce<Record<string, Array<{ type: string; value: string }>>>((acc, record) => {
      const label = record.name.trim() || '@';
      acc[label] = acc[label] ?? [];
      acc[label].push({ type: record.type, value: record.value });
      return acc;
    }, {});

    try {
      await readJson<Record<string, unknown>>(`/zone/${encodeURIComponent(selectedName)}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ records: zone }),
      });
      setNameMessage('Saved local zone draft.');
    } catch (error) {
      setNameMessage(getErrorMessage(error, 'Save failed.'));
    }
  };

  const publishZone = async () => {
    if (!selectedName) {
      return;
    }

    const zone = records.reduce<Record<string, Array<{ type: string; value: string }>>>((acc, record) => {
      const label = record.name.trim() || '@';
      acc[label] = acc[label] ?? [];
      acc[label].push({ type: record.type, value: record.value });
      return acc;
    }, {});

    try {
      setNameMessage('Saving draft and preparing publish...');
      // 1. Automatically save local draft first
      await readJson<Record<string, unknown>>(`/zone/${encodeURIComponent(selectedName)}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ records: zone }),
      });

      // 2. Publish to DHT
      await readJson<Record<string, unknown>>(`/zone/${encodeURIComponent(selectedName)}/publish`, { method: 'POST' });
      setNameMessage('Saved draft and published to the Kinetic DHT.');
    } catch (error) {
      setNameMessage(getErrorMessage(error, 'Publish failed.'));
    }
  };

  const resolve = async () => {
    const trimmed = resolveName.trim();
    if (!trimmed) {
      return;
    }

    setResolveResult({ state: 'loading' });
    try {
      const data = await readJson<Record<string, unknown>>(`/resolve/${encodeURIComponent(trimmed)}`);
      setResolveResult({ state: 'success', data });
    } catch (error) {
      setResolveResult({
        state: 'error',
        message: getErrorMessage(error, 'Resolution failed.'),
      });
    }
  };

  const startRegistration = async () => {
    const trimmed = registerName.trim();
    if (!trimmed) {
      return;
    }

    try {
      const response = await readJson<{ task_id: string }>('/vdf/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: trimmed, iterations: 10000 }),
      });
      setVdfTaskId(response.task_id);
      setVdfStatus({ status: 'Queued', progress: 0 });
    } catch (error) {
      setVdfStatus({
        status: 'Failed',
        progress: 0,
        error: getErrorMessage(error, 'Registration failed to start.'),
      });
    }
  };

  const startRenewal = async () => {
    if (!selectedName) return;
    try {
      const response = await readJson<{ task_id: string }>('/vdf/renew', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: selectedName, iterations: 10000 }),
      });
      setVdfTaskId(response.task_id);
      setVdfStatus({ status: 'Queued', progress: 0 });
      setNameMessage(`Renewal task ${response.task_id} started. Check VDF Dashboard.`);
    } catch (error) {
      setNameMessage(getErrorMessage(error, 'Renewal failed to start.'));
    }
  };

  const updateRecord = (id: string, field: keyof DnsRecord, value: string) => {
    setRecords((current) => current.map((record) => (record.id === id ? { ...record, [field]: value } : record)));
  };

  const installProfile = async () => {
    setIsInstalling(true);
    setInstallMessage('Requesting administrator permission...');

    try {
      const result = await invoke<string>('install_profile', {
        profile: selectedProfile,
        clean: cleanMode,
      });
      setInstallMessage(result);
      await refresh();
    } catch (error) {
      setInstallMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setIsInstalling(false);
    }
  };

  const sections = [
    { id: 'control', label: 'Overview', icon: Activity },
    { id: 'identity', label: 'Identity', icon: ShieldCheck },
    { id: 'names', label: 'Names', icon: Globe2 },
    { id: 'mempool', label: 'Mempool', icon: FileClock },
    { id: 'resolver', label: 'Resolver', icon: Search },
    { id: 'engine', label: 'Engine', icon: ServerCog },
    { id: 'preferences', label: 'Preferences', icon: SlidersHorizontal },
  ] as const;

  const installProfiles = [
    {
      id: 'complete' as const,
      name: 'Complete Setup (Recommended)',
      icon: Sparkles,
      summary: 'Installs the background daemon and configures your OS to natively resolve .kin domains.',
      includes: 'Daemon, CLI, DNS Server',
    },
    {
      id: 'minimal' as const,
      name: 'Minimal Setup (Strict Networks)',
      icon: ShieldCheck,
      summary: 'Installs the daemon without modifying any OS network configurations. Best for corporate VPNs.',
      includes: 'Daemon, CLI',
    },
  ];

  const HealthIcon = health.icon;
  const progress = vdfStatus?.progress ?? 0;

  return (
    <div className="min-h-screen bg-[radial-gradient(circle_at_8%_4%,rgba(132,204,22,0.13),transparent_26%),radial-gradient(circle_at_92%_12%,rgba(99,102,241,0.18),transparent_30%),radial-gradient(circle_at_72%_90%,rgba(249,115,22,0.08),transparent_24%),linear-gradient(135deg,#08090d_0%,#151722_52%,#090a0f_100%)] text-zinc-200">
      <div className="flex min-h-screen min-w-0">
        <aside className="w-64 shrink-0 border-r border-white/10 bg-[#080b0f]/82 px-5 py-6 backdrop-blur-xl xl:w-[17.5rem]">
          <div className="flex items-center gap-3">
            <div className="grid h-10 w-10 shrink-0 place-items-center rounded-md border border-lime-300/30 bg-lime-300/10">
              <Sparkles size={20} className="text-lime-200" />
            </div>
            <div className="min-w-0">
              <div className="text-lg font-semibold tracking-tight text-white">Kinetic</div>
              <div className="text-xs text-zinc-500">Desktop</div>
            </div>
          </div>

          <div className="mt-8 rounded-lg border border-white/10 bg-white/[0.045] p-4">
            <div className="flex items-center justify-between gap-3">
              <StatusPill state={health.state} label={health.label} />
              <HealthIcon size={18} className={classNames(health.state === 'good' && 'text-lime-300', health.state === 'warn' && 'text-orange-300', health.state === 'bad' && 'text-rose-300', health.state === 'neutral' && 'text-zinc-400', health.icon === Loader2 && 'animate-spin')} />
            </div>
            <div className="mt-4 text-sm leading-6 text-zinc-400">
              {daemonState === 'offline'
                ? 'Start the Kinetic daemon to enable live name management and resolution.'
                : 'Local API, resolver tools, and zone workspace are ready.'}
            </div>
          </div>

          <nav className="mt-8 space-y-1.5">
            {sections.map((section) => {
              const Icon = section.icon;
              return (
                <button
                  key={section.id}
                  onClick={() => setActiveSection(section.id)}
                  className={classNames(
                    'flex h-11 w-full items-center gap-3 rounded-md px-3 text-left text-sm font-medium transition',
                    activeSection === section.id
                      ? 'bg-lime-100 text-zinc-950 shadow-sm'
                      : 'text-zinc-400 hover:bg-white/[0.06] hover:text-zinc-100',
                  )}
                >
                  <Icon size={18} className="shrink-0" />
                  <span className="truncate">{section.label}</span>
                </button>
              );
            })}
          </nav>

          <div className="mt-8 border-t border-white/10 pt-5 text-xs leading-relaxed text-zinc-500">
            Local resolver, names, and engine controls.
          </div>

        </aside>

        <main className="min-w-0 flex-1 overflow-y-auto">
          <div className="mx-auto w-full max-w-7xl px-5 py-5 lg:px-7">
            <header className="relative overflow-hidden rounded-lg border border-white/10 bg-[#171a24]/72 p-5 shadow-[0_24px_80px_rgba(0,0,0,0.26)] lg:p-6">
              <div className="absolute -right-20 -top-28 h-52 w-80 rotate-12 bg-indigo-400/14 blur-3xl" />
              <div className="absolute -left-16 bottom-0 h-24 w-56 bg-orange-400/8 blur-3xl" />
              <div className="relative flex flex-col gap-4 min-[880px]:flex-row min-[880px]:items-center min-[880px]:justify-between">
                <div className="min-w-0">
                  <div className="text-sm font-medium text-lime-200">Kinetic Desktop</div>
                  <h1 className="mt-1 max-w-3xl text-2xl font-semibold tracking-tight text-white lg:text-3xl">Resolver, identity, and engine status.</h1>
                </div>
                <button
                  onClick={refresh}
                  className="inline-flex h-10 w-fit items-center gap-2 rounded-md border border-white/10 bg-zinc-950/70 px-4 text-sm font-medium text-zinc-100 transition hover:border-lime-300/40 hover:text-lime-100"
                >
                  <RefreshCw size={16} className={isRefreshing ? 'animate-spin' : ''} />
                  Refresh
                </button>
              </div>
            </header>

            {activeSection === 'control' && (
              <div className="mt-7 grid grid-cols-12 gap-5">
                <Panel className="col-span-12 p-5 xl:col-span-8 xl:p-6">
                  <SectionHeader eyebrow="Overview" title="Local network posture" />
                  <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
                    <Metric icon={Network} label="Peers" value={String(networkStatus?.peers ?? 0)} note="DHT neighbors seen by daemon" />
                    <Metric icon={Database} label="DHT size" value={String(networkStatus?.dht_size ?? 0)} note="Known distributed records" />
                    <Metric icon={Clock3} label="Uptime" value={String(networkStatus?.uptime ?? 'Unknown')} note="Daemon reported runtime" />
                    <Metric icon={Activity} label="NAT Status" value={String(networkStatus?.nat_status ?? 'Unknown')} note="Network accessibility" />
                    <Metric icon={ServerCog} label="Drand Pulse" value={String(networkStatus?.drand_pulse ?? 0)} note="Current randomness round" />
                    <Metric icon={Globe2} label="Names" value={String(ownedNames.length)} note="Locally owned .kin names" />
                  </div>

                  <div className="mt-6 rounded-md border border-white/10 bg-black/20 p-4">
                    <div className="flex items-start gap-3">
                      <CircleDot size={18} className="mt-0.5 shrink-0 text-indigo-300" />
                      <div className="min-w-0">
                        <div className="text-sm font-semibold text-zinc-100">Resolution path</div>
                        <div className="text-sm leading-6 text-zinc-500">Browser and apps ask normal DNS. Kinetic intercepts only `.kin`, then checks local zone data and the DHT.</div>
                      </div>
                    </div>
                    <div className="mt-5 grid grid-cols-1 gap-3 text-sm text-zinc-400 min-[720px]:grid-cols-2 2xl:grid-cols-5">
                      {['App request', 'Split-DNS', 'Daemon API', 'Kademlia DHT', 'Verified answer'].map((step, index) => (
                        <div key={step} className="flex min-w-0 items-center gap-3 rounded-md border border-white/10 bg-[#0a0c12] px-3 py-3">
                          <span className="grid h-6 w-6 shrink-0 place-items-center rounded bg-zinc-800 text-xs text-lime-100">{index + 1}</span>
                          <span className="min-w-0 break-words">{step}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                </Panel>

                <Panel className="col-span-12 p-5 xl:col-span-4 xl:p-6">
                  <SectionHeader eyebrow="Next Actions" title="Useful checks" />
                  <div className="mt-6 space-y-3">
                    <button onClick={() => setActiveSection('resolver')} className="flex w-full items-center justify-between gap-3 rounded-md border border-white/10 bg-white/[0.035] px-4 py-3 text-left text-sm text-zinc-200 transition hover:border-indigo-300/35">
                      Test a .kin name <ArrowRight size={16} />
                    </button>
                    <button onClick={() => setActiveSection('names')} className="flex w-full items-center justify-between gap-3 rounded-md border border-white/10 bg-white/[0.035] px-4 py-3 text-left text-sm text-zinc-200 transition hover:border-indigo-300/35">
                      Edit zone records <ArrowRight size={16} />
                    </button>
                    <button onClick={() => setActiveSection('engine')} className="flex w-full items-center justify-between gap-3 rounded-md border border-white/10 bg-white/[0.035] px-4 py-3 text-left text-sm text-zinc-200 transition hover:border-indigo-300/35">
                      Check OS integration <ArrowRight size={16} />
                    </button>
                  </div>
                </Panel>

                <Panel className="col-span-12 p-5 xl:p-6">
                  <SectionHeader eyebrow="Activity" title="Recent local evidence" />
                  <div className="mt-6 grid grid-cols-1 gap-3 min-[900px]:grid-cols-3">
                    <div className="rounded-md border border-white/10 bg-white/[0.035] p-4">
                      <ShieldCheck size={20} className="text-lime-300" />
                      <div className="mt-3 text-sm font-semibold text-slate-100">Identity stays local</div>
                      <p className="mt-1 text-sm leading-6 text-zinc-500">Keys and zone files are managed by the daemon on this device.</p>
                    </div>
                    <div className="rounded-md border border-white/10 bg-white/[0.035] p-4">
                      <FileClock size={20} className="text-indigo-300" />
                      <div className="mt-3 text-sm font-semibold text-slate-100">Proof-of-time visible</div>
                      <p className="mt-1 text-sm leading-6 text-zinc-500">Registration exposes commit, VDF, reveal, and publish progress.</p>
                    </div>
                    <div className="rounded-md border border-white/10 bg-white/[0.035] p-4">
                      <KeyRound size={20} className="text-orange-300" />
                      <div className="mt-3 text-sm font-semibold text-slate-100">Trust is inspectable</div>
                      <p className="mt-1 text-sm leading-6 text-zinc-500">Resolver output shows the underlying reveal payload for debugging.</p>
                    </div>
                  </div>
                </Panel>
              </div>
            )}

            {activeSection === 'identity' && (
              <div className="mt-7 grid grid-cols-12 gap-5">
                <Panel className="col-span-12 p-5 xl:col-span-7 xl:p-6">
                  <SectionHeader eyebrow="Security" title="Node Identity" />
                  <div className="mt-6 text-sm text-zinc-400 leading-relaxed">
                    Your local identity is represented by a 24-word seed phrase. This phrase is derived one-way into an Ed25519 signing key used to authorize your domain registrations and transfers.
                  </div>
                  
                  {identityMessage && (
                    <div className="mt-6 rounded-md border border-lime-500/30 bg-lime-500/10 px-4 py-3 text-sm text-lime-200">
                      {identityMessage}
                    </div>
                  )}

                  {!seedPhrase ? (
                    <div className="mt-8">
                      <h3 className="text-sm font-semibold text-zinc-100">Generate a New Identity</h3>
                      <p className="mt-2 text-xs text-zinc-500 mb-4">Creates a new random 24-word master seed.</p>
                      <button 
                        onClick={handleGenerateSeed}
                        className="inline-flex h-10 items-center gap-2 rounded-md bg-indigo-500 px-4 text-sm font-medium text-white hover:bg-indigo-400 transition"
                      >
                        <ShieldCheck size={16} /> Generate Master Seed
                      </button>
                    </div>
                  ) : (
                    <div className="mt-8 rounded-md border border-orange-500/30 bg-orange-500/10 p-5">
                      <div className="flex items-start gap-3">
                        <AlertTriangle className="mt-0.5 shrink-0 text-orange-400" size={20} />
                        <div className="min-w-0 flex-1">
                          <h3 className="text-sm font-bold text-orange-200 uppercase tracking-widest">🚨 Backup Immediately 🚨</h3>
                          <p className="mt-2 text-sm text-orange-200/80 leading-relaxed">
                            Write down this 24-word seed phrase and store it safely. This is a one-way derivation. You will <strong>NEVER</strong> be able to view this phrase again.
                          </p>
                          <div className="mt-4 grid grid-cols-3 gap-2 sm:grid-cols-4 md:grid-cols-6 rounded-md border border-black/50 bg-black/40 p-4">
                            {seedPhrase.split(' ').map((word, idx) => (
                              <div key={idx} className="flex gap-1.5">
                                <span className="text-[10px] text-zinc-500 mt-1">{idx + 1}.</span>
                                <span className="font-mono text-sm text-lime-100">{word}</span>
                              </div>
                            ))}
                          </div>
                          
                          <label className="mt-6 flex items-center gap-3 cursor-pointer">
                            <input 
                              type="checkbox" 
                              checked={backupChecked} 
                              onChange={(e) => setBackupChecked(e.target.checked)}
                              className="h-4 w-4 rounded border-white/10 bg-black/30 text-indigo-500 focus:ring-indigo-500 focus:ring-offset-zinc-900" 
                            />
                            <span className="text-sm text-zinc-300 select-none">I have securely backed up these 24 words.</span>
                          </label>

                          <button 
                            onClick={() => handleSaveIdentity(seedPhrase)}
                            disabled={!backupChecked}
                            className="mt-6 inline-flex h-10 items-center gap-2 rounded-md bg-orange-500 px-6 text-sm font-medium text-white hover:bg-orange-400 disabled:opacity-50 disabled:cursor-not-allowed transition"
                          >
                            Save & Initialize Identity
                          </button>
                        </div>
                      </div>
                    </div>
                  )}
                </Panel>

                <Panel className="col-span-12 p-5 xl:col-span-5 xl:p-6">
                  <SectionHeader eyebrow="Recovery" title="Restore Identity" />
                  <div className="mt-6">
                    <p className="text-sm text-zinc-400 mb-4 leading-relaxed">
                      If you already have a 24-word seed phrase, you can restore your identity here.
                    </p>
                    <textarea 
                      value={restorePhrase}
                      onChange={(e) => setRestorePhrase(e.target.value)}
                      placeholder="Paste your 24-word seed phrase here..."
                      className="w-full h-32 rounded-md border border-white/10 bg-black/30 p-3 text-sm text-zinc-100 placeholder:text-zinc-600 outline-none ring-indigo-300/30 focus:ring-2 resize-none"
                    />
                    <div className="mt-4 flex justify-end">
                      <button 
                        onClick={() => handleSaveIdentity(restorePhrase)}
                        disabled={!restorePhrase.trim()}
                        className="inline-flex h-10 items-center gap-2 rounded-md border border-indigo-500/50 bg-indigo-500/10 px-4 text-sm font-medium text-indigo-200 hover:bg-indigo-500/20 disabled:opacity-50 disabled:cursor-not-allowed transition"
                      >
                        <RefreshCw size={16} /> Restore & Restart
                      </button>
                    </div>
                  </div>
                </Panel>
              </div>
            )}

            {activeSection === 'mempool' && (
              <div className="mt-7 grid grid-cols-1 gap-5">
                <Panel className="p-5 xl:p-6">
                  <SectionHeader eyebrow="VDF Worker" title="Active VDF Tasks" />
                  <div className="mt-6">
                    {mempoolData && Object.keys(mempoolData.active_tasks).length > 0 ? (
                      <div className="space-y-3">
                        {Object.entries(mempoolData.active_tasks).map(([id, task]) => (
                          <div key={id} className="rounded-md border border-white/10 bg-[#0a0c12] p-4 text-sm text-zinc-300">
                            <div className="flex items-center justify-between mb-2">
                              <span className="font-semibold text-lime-200">Blind Challenge: {id.substring(0, 16)}...</span>
                              <StatusPill state={task.status === 'Completed' ? 'good' : task.status === 'Failed' ? 'bad' : 'warn'} label={task.status ?? 'Unknown'} />
                            </div>
                            <div className="grid grid-cols-2 gap-4">
                              <div><span className="text-zinc-500">Progress:</span> {task.progress ?? 0}%</div>
                              <div><span className="text-zinc-500">Iterations:</span> {task.iterations ?? 0}</div>
                            </div>
                            {task.error && <div className="mt-2 text-rose-400">Error: {task.error}</div>}
                          </div>
                        ))}
                      </div>
                    ) : (
                      <div className="text-sm text-zinc-500">No active VDF generation tasks.</div>
                    )}
                  </div>
                </Panel>

                <Panel className="p-5 xl:p-6">
                  <SectionHeader eyebrow="Queue" title="Pending VDF Jobs (Mempool)" />
                  <div className="mt-6">
                    {mempoolData && mempoolData.queue.length > 0 ? (
                      <div className="space-y-3">
                        {mempoolData.queue.map((item, idx) => (
                          <div key={idx} className="flex items-center justify-between rounded-md border border-white/10 bg-[#0a0c12] p-4 text-sm text-zinc-300">
                            <div>
                              <div className="font-medium text-slate-100">Job #{idx + 1}</div>
                              <div className="text-xs text-zinc-500 mt-1">Blind Challenge: {Array.isArray(item.request.challenge_hash) ? item.request.challenge_hash.map((b: number) => b.toString(16).padStart(2, '0')).join('').substring(0, 16) : 'Unknown'}...</div>
                            </div>
                            <div className="text-right">
                              <div className="text-xs text-zinc-400">PoW Nonce: {item.request.hashcash_nonce}</div>
                              <div className="text-xs text-zinc-400">Time: {new Date(item.timestamp.secs_since_epoch * 1000).toLocaleString()}</div>
                            </div>
                          </div>
                        ))}
                      </div>
                    ) : (
                      <div className="text-sm text-zinc-500">Mempool is empty.</div>
                    )}
                  </div>
                </Panel>
                
                <div className="rounded-md border border-white/10 bg-black/20 p-4">
                  <div className="flex items-start gap-3">
                    <ShieldCheck size={18} className="mt-0.5 shrink-0 text-lime-300" />
                    <div className="min-w-0">
                      <div className="text-sm font-semibold text-zinc-100">Privacy-Preserving Block Production</div>
                      <div className="text-sm leading-6 text-zinc-500">
                        The Mempool uses delegated <strong>Blind Challenges</strong>. This means your node computes time-lock proofs for other network participants without ever knowing the actual plaintext names they are registering, ensuring front-running protection and zero-knowledge block production.
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            )}

            {activeSection === 'names' && (
              <div className="mt-7 grid grid-cols-12 gap-5">
                <Panel className="col-span-12 p-5 xl:col-span-3">
                  <SectionHeader eyebrow="Owned" title="Names" />
                  <div className="mt-5 space-y-2">
                    {ownedNames.length === 0 ? (
                      <div className="rounded-md border border-dashed border-slate-700 px-4 py-8 text-center text-sm text-slate-500">
                        No local names yet.
                      </div>
                    ) : (
                      ownedNames.map((name) => (
                        <button
                          key={name}
                          onClick={() => setSelectedName(name)}
                          className={classNames(
                            'flex w-full items-center justify-between rounded-md border px-3 py-3 text-left text-sm transition',
                            selectedName === name
                              ? 'border-indigo-300/35 bg-indigo-400/10 text-indigo-100'
                              : 'border-white/10 bg-white/[0.035] text-zinc-300 hover:border-white/20',
                          )}
                        >
                          {normalizeDisplayName(name)}
                          <Globe2 size={16} />
                        </button>
                      ))
                    )}
                  </div>
                </Panel>

                <Panel className="col-span-12 min-w-0 p-5 xl:col-span-9">
                  <div className="flex flex-wrap items-start justify-between gap-4">
                    <SectionHeader eyebrow="Zone Workspace" title={selectedName ? normalizeDisplayName(selectedName) : 'Select a name'} />
                    <div className="flex gap-2">
                      <button onClick={() => setRecords((current) => [...current, createRecord()])} className="inline-flex h-10 items-center gap-2 rounded-md border border-white/10 bg-white/[0.045] px-3 text-sm text-zinc-100 hover:border-indigo-300/40">
                        <Plus size={16} />
                        Record
                      </button>
                      <button onClick={saveZone} disabled={!selectedName} className="inline-flex h-10 items-center gap-2 rounded-md border border-white/10 bg-white/[0.045] px-3 text-sm text-zinc-100 hover:border-indigo-300/40 disabled:cursor-not-allowed disabled:opacity-50">
                        <Save size={16} />
                        Save Draft
                      </button>
                      <button onClick={publishZone} disabled={!selectedName} className="inline-flex h-10 items-center gap-2 rounded-md border border-transparent bg-indigo-500 px-4 text-sm font-medium text-white hover:bg-indigo-400 disabled:cursor-not-allowed disabled:opacity-50">
                        <UploadCloud size={16} />
                        Publish Zone
                      </button>
                      <button onClick={startRenewal} disabled={!selectedName || vdfTaskId !== null} className="inline-flex h-10 items-center gap-2 rounded-md border border-white/10 bg-white/[0.045] px-3 text-sm text-zinc-100 hover:border-lime-300/40 hover:text-lime-200 disabled:cursor-not-allowed disabled:opacity-50">
                        <RefreshCw size={16} />
                        Renew Name
                      </button>
                    </div>
                  </div>

                  {nameMessage && <div className="mt-4 rounded-md border border-white/10 bg-white/[0.04] px-4 py-3 text-sm text-zinc-300">{nameMessage}</div>}

                  <div className="mt-5 overflow-x-auto rounded-md border border-white/10">
                    <div className="min-w-[720px]">
                    <div className="grid grid-cols-[1.1fr_0.75fr_2fr_72px] border-b border-white/10 bg-black/25 px-4 py-3 text-xs font-semibold uppercase tracking-[0.14em] text-zinc-500">
                      <div>Host</div>
                      <div>Type</div>
                      <div>Value</div>
                      <div />
                    </div>
                    {records.length === 0 ? (
                      <div className="px-4 py-12 text-center text-sm text-zinc-500">No records saved for this name yet.</div>
                    ) : (
                      records.map((record) => (
                        <div key={record.id} className="grid grid-cols-[1.1fr_0.75fr_2fr_72px] gap-3 border-b border-white/5 px-4 py-3 last:border-b-0">
                          <input value={record.name} onChange={(event) => updateRecord(record.id, 'name', event.target.value)} className="h-10 rounded-md border border-white/10 bg-black/30 px-3 text-sm text-zinc-100 outline-none ring-indigo-300/30 focus:ring-2" />
                          <select value={record.type} onChange={(event) => updateRecord(record.id, 'type', event.target.value)} className="h-10 rounded-md border border-white/10 bg-black/30 px-3 text-sm text-zinc-100 outline-none ring-indigo-300/30 focus:ring-2">
                            {recordTypes.map((type) => (
                              <option key={type} value={type}>
                                {type}
                              </option>
                            ))}
                          </select>
                          <input value={record.value} onChange={(event) => updateRecord(record.id, 'value', event.target.value)} className="h-10 rounded-md border border-white/10 bg-black/30 px-3 text-sm text-zinc-100 outline-none ring-indigo-300/30 focus:ring-2" />
                          <button onClick={() => setRecords((current) => current.filter((item) => item.id !== record.id))} className="h-10 rounded-md border border-white/10 text-sm text-rose-300 hover:border-rose-500/40 hover:bg-rose-500/10">
                            Clear
                          </button>
                        </div>
                      ))
                    )}
                    </div>
                  </div>

                  <div className="mt-6 rounded-md border border-white/10 bg-white/[0.035] p-4">
                    <div className="text-sm font-semibold text-slate-100">Register a new name</div>
                    <div className="mt-3 flex gap-3">
                      <input value={registerName} onChange={(event) => setRegisterName(event.target.value)} placeholder="yourname.kin" disabled={vdfTaskId !== null} className="h-10 min-w-0 flex-1 rounded-md border border-white/10 bg-black/30 px-3 text-sm text-zinc-100 outline-none ring-indigo-300/30 focus:ring-2 disabled:opacity-50" />
                      <button onClick={startRegistration} disabled={!registerName || vdfTaskId !== null} className="inline-flex h-10 shrink-0 items-center gap-2 rounded-md border border-indigo-300/30 bg-indigo-400/10 px-4 text-sm font-medium text-indigo-100 hover:bg-indigo-400/15 disabled:cursor-not-allowed disabled:opacity-50">
                        <Rocket size={16} />
                        Start
                      </button>
                    </div>
                    {vdfStatus && (
                      <div className="mt-4">
                        <div className="mb-2 flex items-center justify-between text-xs text-zinc-400">
                          <span>{vdfStatus.status ?? 'Working'}</span>
                          <span>{progress}%</span>
                        </div>
                        <div className="h-2 overflow-hidden rounded-full bg-zinc-800">
                          <div className="h-full rounded-full bg-indigo-300 transition-all" style={{ width: `${progress}%` }} />
                        </div>
                        {vdfStatus.error && <div className="mt-2 text-sm text-rose-300">{vdfStatus.error}</div>}
                      </div>
                    )}
                  </div>
                </Panel>
              </div>
            )}

            {activeSection === 'resolver' && (
              <div className="mt-7 grid grid-cols-12 gap-5">
                <Panel className="col-span-12 p-5 xl:col-span-5 xl:p-6">
                  <SectionHeader eyebrow="Resolver Inspector" title="Test a .kin answer" />
                  <div className="mt-6 flex gap-3">
                    <input value={resolveName} onChange={(event) => setResolveName(event.target.value)} onKeyDown={(event) => event.key === 'Enter' && resolve()} className="h-11 min-w-0 flex-1 rounded-md border border-white/10 bg-black/30 px-3 text-sm text-zinc-100 outline-none ring-indigo-300/30 focus:ring-2" />
                    <button onClick={resolve} className="inline-flex h-11 shrink-0 items-center gap-2 rounded-md border border-indigo-300/30 bg-indigo-400/10 px-4 text-sm font-medium text-indigo-100 hover:bg-indigo-400/15">
                      {resolveResult.state === 'loading' ? <Loader2 size={16} className="animate-spin" /> : <Search size={16} />}
                      Resolve
                    </button>
                  </div>
                  <div className="mt-6 space-y-3 text-sm text-slate-500">
                    <div className="flex items-center gap-3 rounded-md border border-slate-800 bg-slate-900/60 px-4 py-3">
                      <HardDrive size={17} className="text-slate-400" />
                      Local daemon checks cache and storage recovery paths.
                    </div>
                    <div className="flex items-center gap-3 rounded-md border border-slate-800 bg-slate-900/60 px-4 py-3">
                      <Network size={17} className="text-slate-400" />
                      DHT lookup fetches the signed reveal payload.
                    </div>
                    <div className="flex items-center gap-3 rounded-md border border-slate-800 bg-slate-900/60 px-4 py-3">
                      <Cpu size={17} className="text-slate-400" />
                      VDF metadata proves the name was not claimed instantly.
                    </div>
                  </div>
                </Panel>

                <Panel className="col-span-12 min-w-0 p-5 xl:col-span-7 xl:p-6">
                  <SectionHeader eyebrow="Evidence" title="Resolution output" />
                  <div className="mt-6">
                    {resolveResult.state === 'idle' && <div className="rounded-md border border-dashed border-slate-700 px-4 py-16 text-center text-sm text-slate-500">Run a lookup to inspect the reveal payload.</div>}
                    {resolveResult.state === 'loading' && <div className="flex items-center gap-3 rounded-md border border-white/10 bg-white/[0.035] px-4 py-6 text-sm text-zinc-300"><Loader2 size={18} className="animate-spin text-indigo-300" />Resolving through local daemon...</div>}
                    {resolveResult.state === 'error' && <div className="rounded-md border border-rose-500/30 bg-rose-500/10 px-4 py-4 text-sm text-rose-200">{resolveResult.message}</div>}
                    {resolveResult.state === 'success' && resolveResult.data && <JsonPreview data={resolveResult.data} />}
                  </div>
                </Panel>
              </div>
            )}

            {activeSection === 'engine' && (
              <div className="mt-7 grid grid-cols-12 gap-5">
                <Panel className="col-span-12 p-5 xl:col-span-7 xl:p-6">
                  <SectionHeader eyebrow="Engine" title="Installation posture" />
                  <div className="mt-6 grid gap-3">
                    <div className="flex items-center justify-between gap-4 rounded-md border border-white/10 bg-white/[0.035] px-4 py-4">
                      <div>
                        <div className="text-sm font-semibold text-slate-100">Kinetic daemon API</div>
                        <div className="text-sm text-slate-500">Expected at 127.0.0.1:16002</div>
                      </div>
                      <StatusPill state={daemonState === 'online' ? 'good' : 'bad'} label={daemonState === 'online' ? 'Reachable' : 'Unavailable'} />
                    </div>
                    <div className="flex items-center justify-between gap-4 rounded-md border border-white/10 bg-white/[0.035] px-4 py-4">
                      <div>
                        <div className="text-sm font-semibold text-slate-100">Split-DNS integration</div>
                        <div className="text-sm text-slate-500">macOS resolver, Linux systemd-resolved, or Windows NRPT.</div>
                      </div>
                      <StatusPill 
                        state={selectedProfile === 'complete' && daemonState === 'online' ? 'good' : 'neutral'} 
                        label={selectedProfile === 'complete' && daemonState === 'online' ? 'Active' : 'Check via installer'} 
                      />
                    </div>
                    <div className="flex items-center justify-between gap-4 rounded-md border border-white/10 bg-white/[0.035] px-4 py-4">
                      <div>
                        <div className="text-sm font-semibold text-slate-100">Local zone storage</div>
                        <div className="text-sm text-slate-500">Zone drafts are saved before publishing to the DHT.</div>
                      </div>
                      <StatusPill state="good" label="Non-custodial" />
                    </div>
                  </div>
                </Panel>

                <Panel className="col-span-12 p-5 xl:col-span-5 xl:p-6">
                  <SectionHeader eyebrow="Install" title="Engine setup" />
                  <div className="mt-5 grid gap-3">
                    {installProfiles.map((profile) => {
                      const Icon = profile.icon;
                      const isSelected = selectedProfile === profile.id;

                      return (
                        <button
                          key={profile.id}
                          onClick={() => setSelectedProfile(profile.id)}
                          className={classNames(
                            'rounded-md border p-4 text-left transition',
                            isSelected
                              ? 'border-indigo-300/40 bg-indigo-400/10'
                              : 'border-white/10 bg-white/[0.035] hover:border-white/20',
                          )}
                        >
                          <div className="flex items-start gap-3">
                            <div className={classNames('grid h-10 w-10 shrink-0 place-items-center rounded-md border', isSelected ? 'border-indigo-300/30 bg-indigo-400/10 text-indigo-100' : 'border-white/10 bg-black/30 text-zinc-400')}>
                              <Icon size={18} />
                            </div>
                            <div>
                              <div className="text-sm font-semibold text-slate-100">{profile.name}</div>
                              <p className="mt-1 text-sm leading-5 text-slate-500">{profile.summary}</p>
                              <div className="mt-2 text-xs text-slate-500">Includes: {profile.includes}</div>
                            </div>
                          </div>
                        </button>
                      );
                    })}
                  </div>

                  <label className={classNames('mt-4 flex cursor-pointer items-start gap-3 rounded-md border p-4 transition', cleanMode ? 'border-rose-500/40 bg-rose-500/10' : 'border-white/10 bg-white/[0.035] hover:border-white/20')}>
                    <input
                      type="checkbox"
                      checked={cleanMode}
                      onChange={(event) => setCleanMode(event.target.checked)}
                      className="mt-1 h-4 w-4 accent-rose-400"
                    />
                    <span>
                      <span className={classNames('block text-sm font-semibold', cleanMode ? 'text-rose-200' : 'text-slate-100')}>Full clean install</span>
                      <span className="mt-1 block text-sm leading-5 text-slate-500">
                        Removes existing binaries and local Kinetic config before reinstalling. This can wipe local identity material.
                      </span>
                    </span>
                  </label>

                  <button
                    onClick={installProfile}
                    disabled={isInstalling}
                    className={classNames(
                      'mt-4 inline-flex h-11 w-full items-center justify-center gap-2 rounded-md border px-4 text-sm font-semibold transition disabled:cursor-not-allowed disabled:opacity-60',
                      cleanMode
                        ? 'border-rose-500/40 bg-rose-500/10 text-rose-100 hover:bg-rose-500/15'
                        : 'border-indigo-300/40 bg-indigo-400/10 text-indigo-100 hover:bg-indigo-400/15',
                    )}
                  >
                    {isInstalling ? <Loader2 size={16} className="animate-spin" /> : <ArrowRight size={16} />}
                    {isInstalling ? 'Installing...' : `Install ${selectedProfile}`}
                  </button>

                  {installMessage && (
                    <div className={classNames('mt-4 rounded-md border px-4 py-3 text-sm', installMessage.toLowerCase().includes('error') || installMessage.toLowerCase().includes('failed') ? 'border-rose-500/30 bg-rose-500/10 text-rose-200' : 'border-lime-300/30 bg-lime-300/10 text-lime-100')}>
                      {installMessage}
                    </div>
                  )}
                </Panel>
              </div>
            )}

            {activeSection === 'preferences' && (
              <div className="mt-7 grid grid-cols-12 gap-5">
                <Panel className="col-span-12 p-5 xl:col-span-7 xl:p-6">
                  <SectionHeader eyebrow="Preferences" title="Appearance" />
                  <div className="mt-6 grid gap-3 md:grid-cols-3">
                    {[
                      { id: 'adaptive' as const, label: 'Adaptive', note: 'Follows system and network state.' },
                      { id: 'dark' as const, label: 'Dark', note: 'Steady low-light interface.' },
                      { id: 'light' as const, label: 'Light', note: 'Reserved for bright environments.' },
                    ].map((option) => (
                      <button
                        key={option.id}
                        onClick={() => setThemeMode(option.id)}
                        className={classNames(
                          'rounded-md border p-4 text-left transition',
                          themeMode === option.id
                            ? 'border-lime-300/40 bg-lime-300/10'
                            : 'border-white/10 bg-white/[0.045] hover:border-white/20',
                        )}
                      >
                        <div className="text-sm font-semibold text-slate-100">{option.label}</div>
                        <div className="mt-2 text-sm leading-5 text-slate-500">{option.note}</div>
                      </button>
                    ))}
                  </div>
                  <div className="mt-6 rounded-md border border-white/10 bg-white/[0.045] p-4">
                    <div className="text-sm font-semibold text-slate-100">Current accent</div>
                    <div className="mt-3 flex gap-2">
                      <span className="h-6 w-10 rounded bg-lime-300" />
                      <span className="h-6 w-10 rounded bg-indigo-400" />
                      <span className="h-6 w-10 rounded bg-orange-400" />
                      <span className="h-6 w-10 rounded bg-rose-400" />
                    </div>
                  </div>
                </Panel>

                <Panel className="col-span-12 p-5 xl:col-span-5 xl:p-6">
                  <SectionHeader eyebrow="Startup" title="Desktop behavior" />
                  <label className="mt-6 flex cursor-pointer items-start gap-3 rounded-md border border-white/10 bg-white/[0.045] p-4 transition hover:border-white/20">
                    <input
                      type="checkbox"
                      checked={launchOnStartup}
                      onChange={(event) => setLaunchOnStartup(event.target.checked)}
                      className="mt-1 h-4 w-4 accent-lime-300"
                    />
                    <span>
                      <span className="block text-sm font-semibold text-slate-100">Launch dashboard on system startup</span>
                      <span className="mt-1 block text-sm leading-5 text-slate-500">Keeps Kinetic visible and available from the tray.</span>
                    </span>
                  </label>
                  <div className="mt-4 rounded-md border border-amber-400/25 bg-amber-400/10 p-4 text-sm leading-6 text-amber-100">
                    Startup persistence needs a small native hook before this preference can write OS settings.
                  </div>
                </Panel>
              </div>
            )}
          </div>
        </main>
      </div>
    </div>
  );
}
