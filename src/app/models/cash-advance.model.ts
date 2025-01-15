export interface CashAdvance {
  id: string;
  employeeId: string;
  amount: number;
  reason: string;
  status: 'PENDING' | 'APPROVED' | 'REJECTED' | 'PAID';
  createdAt: Date;
  approvedAt?: Date;
  approvedBy?: string;
}
