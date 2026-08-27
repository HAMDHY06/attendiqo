const productionMajor = 22;

export const assertSupportedNodeRuntime = ({
  version = process.versions.node,
  emulator = process.env.FUNCTIONS_EMULATOR === 'true'
    || Boolean(process.env.FIREBASE_EMULATOR_HUB),
} = {}) => {
  const major = Number.parseInt(String(version).split('.')[0], 10);
  if (major === productionMajor) {
    return { major, production: true, emulatorFallback: false };
  }
  if (emulator && major === 24) {
    return { major, production: false, emulatorFallback: true };
  }
  throw new Error(`Unsupported Node runtime. Expected Node ${productionMajor}.`);
};
