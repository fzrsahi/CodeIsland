/**
 * Morrow — Interactive Client Logic & Release Fetcher
 * Features:
 *   1. Dynamic Island tab switcher (Agents, Lyrics, Git)
 *   2. Client-side OS auto-detection (macOS .dmg, Windows .exe, Linux .AppImage)
 *   3. GitHub Releases live version & aggregated download counter
 *   4. Invisible non-blocking telemetry beacon (sendBeacon)
 */

(function () {
  'use strict';

  // --- Configuration ---
  const REPO = 'fzrsahi/Morrow';
  const TELEMETRY_ENDPOINT = 'https://azhr.cloud/api/track';
  const GITHUB_API_RELEASES = `https://api.github.com/repos/${REPO}/releases`;
  const GITHUB_API_REPO = `https://api.github.com/repos/${REPO}`;

  // Default Fallbacks
  const FALLBACK_VERSION = 'v1.0.41';
  const DEFAULT_DOWNLOAD_URLS = {
    macos: `https://github.com/${REPO}/releases/latest/download/Morrow.dmg`,
    windows: `https://github.com/${REPO}/releases/latest/download/Morrow-Setup.exe`,
    linux: `https://github.com/${REPO}/releases/latest/download/Morrow.AppImage`,
  };

  // --- 1. Detect Client OS ---
  function detectOS() {
    const userAgent = navigator.userAgent || '';
    const platform = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || '';

    if (/Mac/i.test(platform) || /Macintosh/i.test(userAgent)) {
      return 'macos';
    } else if (/Win/i.test(platform) || /Windows/i.test(userAgent)) {
      return 'windows';
    } else if (/Linux/i.test(platform) || /Linux/i.test(userAgent)) {
      return 'linux';
    }
    return 'macos'; // default recommendation
  }

  const currentOS = detectOS();

  // --- 2. Update Primary Download CTA based on OS ---
  function setupDownloadButton(releaseData) {
    const primaryBtn = document.getElementById('primary-download-btn');
    const osIcon = document.getElementById('os-icon');
    const downloadTitle = document.getElementById('download-title');
    const downloadArch = document.getElementById('download-arch');

    if (!primaryBtn) return;

    let targetUrl = DEFAULT_DOWNLOAD_URLS[currentOS];
    let icon = '🍏';
    let title = 'Download for macOS';
    let arch = 'Universal .dmg • macOS 14+ Sonoma';

    // If release assets are available from GitHub API, resolve canonical asset
    if (releaseData && Array.isArray(releaseData.assets)) {
      if (currentOS === 'macos') {
        const macAsset = releaseData.assets.find(a => a.name.endsWith('.dmg'));
        if (macAsset) targetUrl = macAsset.browser_download_url;
      } else if (currentOS === 'windows') {
        const winAsset = releaseData.assets.find(a => a.name.endsWith('.exe'));
        if (winAsset) targetUrl = winAsset.browser_download_url;
      } else if (currentOS === 'linux') {
        const linAsset = releaseData.assets.find(a => a.name.endsWith('.AppImage') || a.name.endsWith('.flatpak'));
        if (linAsset) targetUrl = linAsset.browser_download_url;
      }
    }

    if (currentOS === 'windows') {
      icon = '🪟';
      title = 'Download for Windows';
      arch = 'x64 Installer .exe • Windows 10/11';
    } else if (currentOS === 'linux') {
      icon = '🐧';
      title = 'Download for Linux';
      arch = 'Portable .AppImage • x86_64';
    }

    osIcon.textContent = icon;
    downloadTitle.textContent = title;
    downloadArch.textContent = arch;
    primaryBtn.href = targetUrl;

    // Attach click telemetry to all download links
    attachDownloadTracking(primaryBtn, currentOS, targetUrl);

    document.querySelectorAll('.alt-link').forEach(link => {
      const os = link.getAttribute('data-os');
      const url = DEFAULT_DOWNLOAD_URLS[os] || primaryBtn.href;
      link.href = url;
      attachDownloadTracking(link, os, url);
    });
  }

  // --- 3. Telemetry Tracking (sendBeacon - Non-Blocking) ---
  function sendTelemetry(eventType, metadata) {
    try {
      const payload = JSON.stringify({
        project: 'Morrow',
        event: eventType,
        os: currentOS,
        path: window.location.pathname,
        referrer: document.referrer || 'direct',
        screen: `${window.innerWidth}x${window.innerHeight}`,
        timestamp: new Date().toISOString(),
        ...metadata,
      });

      if (navigator.sendBeacon) {
        navigator.sendBeacon(TELEMETRY_ENDPOINT, payload);
      } else {
        fetch(TELEMETRY_ENDPOINT, {
          method: 'POST',
          body: payload,
          headers: { 'Content-Type': 'application/json' },
          keepalive: true,
          mode: 'no-cors'
        }).catch(() => {});
      }
    } catch (_) {
      // Invisible telemetry should never throw or interrupt UX
    }
  }

  function attachDownloadTracking(element, osName, targetUrl) {
    element.addEventListener('click', function () {
      sendTelemetry('download_click', {
        target_os: osName,
        target_url: targetUrl
      });
    });
  }

  // Record initial page visit
  sendTelemetry('page_view', {});

  // --- 4. Interactive Simulator Tab Switcher ---
  function setupTabs() {
    const tabs = document.querySelectorAll('.demo-tab');
    const panes = {
      agents: document.getElementById('pane-agents'),
      lyrics: document.getElementById('pane-lyrics'),
      git: document.getElementById('pane-git'),
    };

    tabs.forEach(tab => {
      tab.addEventListener('click', function () {
        const target = this.getAttribute('data-tab');

        tabs.forEach(t => {
          t.classList.remove('active');
          t.setAttribute('aria-selected', 'false');
        });

        this.classList.add('active');
        this.setAttribute('aria-selected', 'true');

        Object.keys(panes).forEach(key => {
          if (panes[key]) {
            panes[key].classList.toggle('active', key === target);
          }
        });
      });
    });
  }

  // --- 5. Fetch Live GitHub Releases & Aggregated Downloads ---
  async function fetchGitHubStats() {
    try {
      const response = await fetch(GITHUB_API_RELEASES);
      if (!response.ok) return;

      const releases = await response.json();
      if (!Array.isArray(releases) || releases.length === 0) return;

      const latestRelease = releases[0];
      const versionTag = latestRelease.tag_name || latestRelease.name || FALLBACK_VERSION;

      // Update release pill
      const pill = document.getElementById('release-version-pill');
      if (pill) {
        pill.textContent = `${versionTag} Release Live`;
      }

      // Calculate aggregated downloads across all releases and platforms
      let totalDownloads = 0;
      releases.forEach(rel => {
        if (Array.isArray(rel.assets)) {
          rel.assets.forEach(asset => {
            totalDownloads += asset.download_count || 0;
          });
        }
      });

      const downloadsText = document.getElementById('total-downloads-text');
      if (downloadsText && totalDownloads > 0) {
        downloadsText.textContent = `⚡ ${totalDownloads.toLocaleString()}+ downloads across all platforms`;
      }

      // Re-configure button with live asset URLs
      setupDownloadButton(latestRelease);
    } catch (_) {
      // Fallback silently
      setupDownloadButton(null);
    }

    // Fetch Star count
    try {
      const repoRes = await fetch(GITHUB_API_REPO);
      if (repoRes.ok) {
        const repoData = await repoRes.json();
        const starEl = document.getElementById('gh-star-count');
        if (starEl && repoData.stargazers_count !== undefined) {
          starEl.textContent = `★ ${repoData.stargazers_count}`;
        }
      }
    } catch (_) {}
  }

  // --- Initialization ---
  document.addEventListener('DOMContentLoaded', () => {
    setupTabs();
    setupDownloadButton(null);
    fetchGitHubStats();
  });
})();
