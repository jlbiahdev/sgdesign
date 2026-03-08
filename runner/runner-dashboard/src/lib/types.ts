export type WorkStatus = 'Submitted' | 'Running' | 'Finished' | 'Failed' | 'Canceled'
export type CommandType = 'Shell' | 'DotNet'

export interface TaskRecord {
  id: number
  externalId: number
  state: WorkStatus
  commandType: CommandType
  exeName: string
  args: string | null
  createdAt: string
}

export interface TaskStateRecord {
  id: number
  taskId: number
  name: WorkStatus
  reason: string | null
  serverId: string | null
  createdAt: string
}

export interface ServerRecord {
  id: string
  friendlyName: string | null
  lastHeartbeatAt: string
}

export interface TaskEvent {
  taskId: number
  state: WorkStatus
  serverId: string | null
  reason: string | null
  at: string
}

export interface SubmitRequest {
  externalId: number
  commandType: CommandType
  exeName: string
  args: string | null
}
