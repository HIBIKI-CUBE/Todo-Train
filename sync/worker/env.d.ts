declare namespace Cloudflare {
  interface Env {
    PAIRING: DurableObjectNamespace;
    DIRECTORY: DurableObjectNamespace;
  }
}

interface Env extends Cloudflare.Env {}
