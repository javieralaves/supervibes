// Lets `node --test` run the server's TypeScript tests: relative imports in src/ leave out ".ts", as the bundler
// allows, so this resolves them to the .ts file. Used by `npm test`.
import { register } from "node:module";

register(
  "data:text/javascript," +
    encodeURIComponent(`
      export async function resolve(specifier, context, next) {
        try {
          return await next(specifier, context);
        } catch (error) {
          if (specifier.startsWith(".") && !/\\.[cm]?[jt]s$/.test(specifier)) return next(specifier + ".ts", context);
          throw error;
        }
      }
    `),
  import.meta.url,
);
