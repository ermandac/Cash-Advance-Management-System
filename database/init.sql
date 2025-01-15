-- Create Database
CREATE DATABASE sakada_db;

-- Connect to the database
\c sakada_db

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users Table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('ADMIN', 'SUPERVISOR', 'EMPLOYEE')),
    access_level INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT TRUE
);

-- Employees Table
CREATE TABLE employees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    department VARCHAR(100),
    supervisor_id UUID REFERENCES employees(id),
    hire_date DATE NOT NULL,
    phone_number VARCHAR(20),
    address TEXT,
    position VARCHAR(100),
    salary_rate NUMERIC(10,2),
    CONSTRAINT fk_supervisor 
        FOREIGN KEY(supervisor_id) 
        REFERENCES employees(id)
        ON DELETE SET NULL
);

-- Cash Advances Table
CREATE TABLE cash_advances (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID NOT NULL REFERENCES employees(id),
    amount NUMERIC(10,2) NOT NULL,
    purpose TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING' 
        CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'PAID')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    approved_by UUID REFERENCES users(id),
    approved_at TIMESTAMP WITH TIME ZONE,
    rejection_reason TEXT,
    payment_date DATE,
    installment_period INTEGER,
    monthly_deduction NUMERIC(10,2)
);

-- Payments Table
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cash_advance_id UUID NOT NULL REFERENCES cash_advances(id),
    amount NUMERIC(10,2) NOT NULL,
    payment_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    payment_type VARCHAR(20) CHECK (payment_type IN ('SALARY_DEDUCTION', 'CASH', 'BANK_TRANSFER')),
    reference_number VARCHAR(50),
    recorded_by UUID REFERENCES users(id)
);

-- Audit Log Table
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    action VARCHAR(50) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_id UUID,
    old_values JSONB,
    new_values JSONB,
    ip_address VARCHAR(45),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better performance
CREATE INDEX idx_cash_advances_employee ON cash_advances(employee_id);
CREATE INDEX idx_cash_advances_status ON cash_advances(status);
CREATE INDEX idx_employees_supervisor ON employees(supervisor_id);
CREATE INDEX idx_audit_logs_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_payments_cash_advance ON payments(cash_advance_id);

-- Create audit trigger function
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_logs (
        user_id,
        action,
        entity_type,
        entity_id,
        old_values,
        new_values
    )
    VALUES (
        current_setting('app.current_user_id', true)::uuid,
        TG_OP,
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        CASE WHEN TG_OP = 'DELETE' THEN row_to_json(OLD)::jsonb ELSE NULL END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN row_to_json(NEW)::jsonb ELSE NULL END
    );
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for auditing
CREATE TRIGGER cash_advances_audit
AFTER INSERT OR UPDATE OR DELETE ON cash_advances
FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

CREATE TRIGGER employees_audit
AFTER INSERT OR UPDATE OR DELETE ON employees
FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- Create views for common queries
CREATE VIEW cash_advance_summary AS
SELECT 
    ca.id,
    e.first_name || ' ' || e.last_name as employee_name,
    ca.amount,
    ca.status,
    ca.created_at,
    COALESCE(SUM(p.amount), 0) as total_paid,
    ca.amount - COALESCE(SUM(p.amount), 0) as remaining_balance
FROM cash_advances ca
JOIN employees e ON ca.employee_id = e.id
LEFT JOIN payments p ON ca.id = p.cash_advance_id
GROUP BY ca.id, e.first_name, e.last_name;

-- Insert default admin user (password: admin123)
INSERT INTO users (
    username,
    password_hash,
    email,
    role,
    access_level
) VALUES (
    'admin',
    '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj6f.CbP0pqu', -- This is a bcrypt hash of 'admin123'
    'admin@sakada.com',
    'ADMIN',
    10
);
