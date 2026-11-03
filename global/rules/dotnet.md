---
paths:
  - "**/*.cs"
---

# .NET anti-patterns

Shapes you would otherwise write. Budget: 10 lines; a new one displaces the weakest.

- Never throw an exception for an expected business error. Return it as a result (`ErrorOr` where the project uses it).
- Never guard a constructor-injected dependency with `?? throw new ArgumentNullException(nameof(x))`. The container never passes null.
- Never wrap an endpoint body in `try/catch (Exception)` to build the error response. The global exception handler does that.
- Never write an async I/O method without a `CancellationToken`, or call an async EF/HttpClient/`Send` method without passing it.
- Never `await` a query inside a `foreach`. Load the set once (`Where(x => ids.Contains(x.Id))`) and look items up in a dictionary.
- Never pass an interpolated `$"..."` string to a logger, and never log emails, names or request objects. Use a message template with ids.
- Never call `DateTime.UtcNow`/`Now` in handlers, domain or repositories. Inject `TimeProvider`.
- Never format or parse a number or date without `CultureInfo.InvariantCulture` or an explicit culture.
- Never use `Enum.TryParse` without `Enum.IsDefined`: it accepts out-of-range numbers.
- Never type a new entity id as a bare `Guid` or `int`. Use a strongly-typed id (`readonly record struct StudentId(Guid Value)`) with its EF value converter. Leave existing `Guid` ids alone unless asked to migrate them.
