# Scope and traceability

The approved issue is an onboarding defect in the existing company public-client
device flow. Registration guidance and reusable enrollment are within scope;
automatic provider mutations or new provider adapters are not.

FR-001/002/003/007/008/009 map to T002; FR-004/005/006 map to T001/T002;
FR-010 maps to T003/T004. Every requirement has an executable owner and acceptance
case. Tests use synthetic HTTP/native callbacks, never live accounts or secrets.
Existing company/broker scope and cancellation remain explicit. No unresolved
clarification prevents implementing the bounded issue; user authorization covers
the spec and build. Final v1.6.1 release metadata is an integration dependency,
not a reason to mix the new flow into that tested runtime.
