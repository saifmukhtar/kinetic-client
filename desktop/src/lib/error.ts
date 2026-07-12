export class KineticApiError extends Error {
  code?: string;
  detail?: string;

  constructor(message: string, code?: string, detail?: string) {
    super(message);
    this.name = 'KineticApiError';
    this.code = code;
    this.detail = detail;
  }
}

export function getErrorMessage(error: unknown, fallback: string): string {
  if (error instanceof KineticApiError) {
    return error.detail ? `${error.message}: ${error.detail}` : error.message;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return fallback;
}
