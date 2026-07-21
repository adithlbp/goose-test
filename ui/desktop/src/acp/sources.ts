import type { SourceEntry, SourceType } from '@aaif/goose-sdk';
import { getAcpClient } from './acpConnection';

const SKILL_SOURCE_TYPES: SourceType[] = ['skill', 'builtinSkill'];

/**
 * Turn a human-typed title into a valid skill name: lowercase ascii letters,
 * digits and hyphens only, no leading/trailing hyphen, max 64 chars.
 * Mirrors `validate_skill_name` in crates/goose/src/skills/mod.rs.
 */
export function skillNameFromTitle(title: string): string {
  return title
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 64)
    .replace(/-+$/g, '');
}

/**
 * Create a global skill (`~/.agents/skills/<name>/SKILL.md`) via the official
 * sources endpoint. `content` is the plain-language instruction body.
 */
export async function createGlobalSkill(
  name: string,
  description: string,
  content: string
): Promise<SourceEntry> {
  const client = await getAcpClient();
  const { source } = await client.goose.sourcesCreate_unstable({
    type: 'skill',
    name,
    description,
    content,
    target: { scope: 'global' },
  });
  return source;
}
const inFlightSkillSourceLoads = new Map<string, Promise<SourceEntry[]>>();

export async function listSkillSources(projectDir: string): Promise<SourceEntry[]> {
  const inFlightLoad = inFlightSkillSourceLoads.get(projectDir);
  if (inFlightLoad) {
    return inFlightLoad;
  }

  const load = loadSkillSources(projectDir);
  inFlightSkillSourceLoads.set(projectDir, load);

  try {
    return await load;
  } finally {
    if (inFlightSkillSourceLoads.get(projectDir) === load) {
      inFlightSkillSourceLoads.delete(projectDir);
    }
  }
}

async function loadSkillSources(projectDir: string): Promise<SourceEntry[]> {
  const client = await getAcpClient();
  const responses = await Promise.all(
    SKILL_SOURCE_TYPES.map((type) =>
      client.goose.sourcesList_unstable({
        type,
        projectDir,
      })
    )
  );

  return responses
    .flatMap((response) => response.sources)
    .sort(
      (a, b) =>
        a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }) ||
        a.path.localeCompare(b.path)
    );
}
