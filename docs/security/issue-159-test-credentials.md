# Review of test credential findings (issue 159)

The line numbers below refer to revision `103f7b965f254ca285d3eddaa78e11d76665d2d9`,
the revision scanned in the issue. These findings are in test sources, not production configuration.

| File and reported lines | Assessment and evidence |
| --- | --- |
| `AuthResourceTest.java`: 85, 124, 149, 176, 216, 251, 281, 306, 606, 660, 691 | Synthetic request values; `SupabaseAuthClient` is injected as a mock. The unauthenticated password-change case is rejected at the HTTP boundary. |
| `IdentityServiceTest.java`: 73, 94, 96, 100, 119, 137, 142, 158, 162 | Synthetic values passed to the service or matched in Mockito stubs. The injected identity-provider client is mocked; comparisons distinguish the current, new and incorrect values. |
| `EmailFailureTest.java`: 95; `WelcomeEmailTest.java`: 126 | Synthetic registration values; the identity-provider client is mocked. |
| `DatabasePrivilegeTest.java`: 60 | `zen_runtime` is the public role name fixed by the migration, not a password. The test must use that name to exercise its grants. |
| `DatabasePrivilegeTest.java`: 63 | A fixed test password was temporarily assigned to real PostgreSQL roles. It is replaced by a fresh random value per test and removed from the runtime role in teardown; the stand-in roles are dropped. No production credential was identified. |
| `DatabasePrivilegeTest.java`: 443, 547 | `anon` is the public name of a stand-in PostgreSQL role, not a credential. The tests connect as that role to verify the grants and row-level security. |

The database tests normally use Quarkus Dev Services' disposable PostgreSQL, but datasource
configuration can be overridden. They execute destructive SQL, including dropping an `auth` schema;
run them only against a disposable test database. A mock and a test profile are boundaries of the
test setup, not proof that an arbitrarily overridden environment is isolated. No finding was
suppressed, and comments describing fixtures do not themselves suppress Snyk alerts.
