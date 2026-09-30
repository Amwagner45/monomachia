import './ui/style.css';
import { Game } from './game';

function boot() {
  const app = document.getElementById('app');
  if (!app) return;
  try {
    new Game(app);
  } catch (err) {
    console.error(err);
    const msg = document.createElement('div');
    msg.style.cssText = 'position:fixed;inset:0;display:grid;place-items:center;padding:24px;text-align:center;color:#eadfca;background:#0f0b0b;font-family:system-ui';
    msg.textContent = 'Monomachia could not start: this browser or device does not support WebGL. Try a recent version of Chrome, Edge, Firefox or Safari on a computer.';
    document.body.appendChild(msg);
  }
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
else boot();
