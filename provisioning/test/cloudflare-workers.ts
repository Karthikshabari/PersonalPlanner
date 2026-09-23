export class DurableObject<T = unknown> {
  constructor(protected readonly ctx: any, protected readonly env: T) {}
}
