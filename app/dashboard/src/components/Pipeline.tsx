// The Overview hero: a change's path through the control plane. Left→right: proposal, multisig
// quorum (real threshold from the Safe Transaction Service, linked), the 72h public review window
// with the screening stack running for the full span, and the two exits — executed, or cancelled
// by a guardian veto at any point in the window.

const eyebrowMono = "font-mono text-[10px] tracking-[0.08em] text-muted whitespace-nowrap";

export function Pipeline({
  safeUrl,
  quorum,
}: {
  safeUrl: string | null;
  quorum: { threshold: number; owners: number } | null;
}) {
  return (
    <div className="relative mt-12 h-[296px] max-md:hidden">
      {/* axis — starts after the proposal marker, ends before the executed badge */}
      <div className="absolute left-[3%] right-[5.6%] top-10 h-[1.5px] bg-[#D6D2C6]" />
      {/* proposed */}
      <div className="absolute left-[2%] top-10 h-[9px] w-[9px] -translate-x-1/2 -translate-y-1/2 rounded-full border-[1.5px] border-muted bg-bg" />
      <div className={`absolute left-0 top-14 ${eyebrowMono}`}>PROPOSED CHANGE</div>
      {/* executed */}
      <div className="absolute left-[97%] top-10 flex h-[22px] w-[22px] -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-ok-tint text-xs font-semibold text-ok">
        ✓
      </div>
      <div className={`absolute left-[97%] top-[60px] -translate-x-1/2 ${eyebrowMono}`}>EXECUTED</div>
      {/* multisig node (real quorum, linked to the Safe) */}
      <a
        href={safeUrl ?? undefined}
        target="_blank"
        rel="noreferrer"
        className="group absolute left-[20%] top-2 z-[2] w-40 -translate-x-1/2 text-center"
      >
        <div className="mx-auto h-16 w-[34px] rounded-[9px] border-[1.5px] border-[#A18A69] bg-panel transition-all group-hover:scale-105 group-hover:bg-bronze-tint" />
        <div className="mt-3 whitespace-nowrap text-[13px] font-semibold text-fg">Multisig approval</div>
        {safeUrl && (
          <div className="mt-1.5">
            <span className="rounded-md bg-bronze-tint px-2 py-0.5 font-mono text-xs text-bronze">
              {quorum ? `${quorum.threshold} of ${quorum.owners} · ` : ""}Safe ↗
            </span>
          </div>
        )}
      </a>
      {/* review window */}
      <div className="absolute left-[57%] top-0.5 -translate-x-1/2 whitespace-nowrap font-mono text-[11px] tracking-[0.1em] text-ok">
        72H
      </div>
      <div className="absolute left-[34%] top-[26px] h-[29px] w-[46%] rounded-2xl border border-[rgba(22,163,74,0.22)] bg-ok-tint" />
      <div className="absolute top-10 z-[3] -ml-[5.5px] -mt-[5.5px] h-[11px] w-[11px] animate-gauntletDot rounded-full bg-ok shadow-[0_0_0_4px_rgba(60,194,123,0.15)]" />
      {/* screening card, running for the full window */}
      <div className="absolute left-[56%] top-[55px] h-10 w-px bg-[rgba(194,64,42,0.45)]" />
      <div className="absolute left-[36%] top-[95px] z-[1] w-[40%] rounded-xl border border-border bg-panel">
        <div className="flex items-center gap-2 px-3.5 py-2.5">
          <span className="h-[7px] w-[7px] shrink-0 animate-scanPulse rounded-full bg-ok" />
          <span className="font-mono text-[10px] tracking-[0.12em] text-fg">SCREENING</span>
          <div className="flex-1" />
          <span className="rounded-md bg-ok-tint px-1.5 py-0.5 font-mono text-[10px] tracking-[0.08em] text-ok">
            CONTINUOUS
          </span>
        </div>
        <div className="flex flex-col gap-2 px-3 pb-3">
          {["Guardian review", "Hypernative automated monitoring"].map((label, i) => (
            <div key={label} className="flex items-center rounded-lg border border-border2 px-3 py-2">
              <span className="text-[12.5px] font-medium text-fg">{label}</span>
              <div className="flex-1" />
              <span className="relative h-[7px] w-[7px] shrink-0">
                <span className="absolute inset-0 rounded-full bg-ok" />
                <span
                  className="absolute inset-0 animate-ping2 rounded-full bg-ok"
                  style={{ animationDelay: `${i * 0.7}s` }}
                />
              </span>
            </div>
          ))}
        </div>
      </div>
      {/* veto exit */}
      <div className="absolute left-[76%] right-[5.6%] top-[183px] h-px bg-[rgba(194,64,42,0.45)]" />
      <div className="absolute left-[78%] top-[168px] whitespace-nowrap font-mono text-[9.5px] tracking-[0.08em] text-high">
        GUARDIAN VETO
      </div>
      <div className="absolute left-[97%] top-[183px] z-[2] flex h-[18px] w-[18px] -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full border border-[rgba(194,64,42,0.4)] bg-high-tint text-[9px] text-high">
        ✕
      </div>
      <div className={`absolute left-[97%] top-[196px] -translate-x-1/2 whitespace-nowrap font-mono text-[9.5px] tracking-[0.04em] text-high`}>
        CANCELLED
      </div>
    </div>
  );
}
