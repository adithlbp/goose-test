import { useState, useEffect, useMemo, useCallback } from 'react';
import type { SourceEntry } from '@aaif/goose-sdk';
import { Zap, AlertCircle, Plus, Lock, Trash2 } from 'lucide-react';
import { ScrollArea } from '../ui/scroll-area';
import { Card } from '../ui/card';
import { Button } from '../ui/button';
import { Input } from '../ui/input';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '../ui/dialog';
import { Skeleton } from '../ui/skeleton';
import { MainPanelLayout } from '../Layout/MainPanelLayout';
import { errorMessage } from '../../utils/conversionUtils';
import { getInitialWorkingDir } from '../../utils/workingDir';
import { defineMessages, useIntl } from '../../i18n';
import { SearchView } from '../conversation/SearchView';
import { getSearchShortcutText } from '../../utils/keyboardShortcuts';
import {
  listSkillSources,
  createGlobalSkill,
  updateGlobalSkill,
  deleteGlobalSkill,
  skillNameFromTitle,
} from '../../acp/sources';
import { toastError, toastSuccess } from '../../toasts';

const i18n = defineMessages({
  errorLoadingSkills: {
    id: 'skillsView.errorLoadingSkills',
    defaultMessage: 'Error Loading Skills',
  },
  tryAgain: {
    id: 'skillsView.tryAgain',
    defaultMessage: 'Try Again',
  },
  noSkillsInstalled: {
    id: 'skillsView.noSkillsInstalled',
    defaultMessage: 'No skills installed',
  },
  noSkillsDescription: {
    id: 'skillsView.noSkillsDescription',
    defaultMessage:
      'Skills are loaded from SKILL.md files in ~/.config/agents/skills/, .goose/skills/, or other supported directories.',
  },
  noMatchingSkills: {
    id: 'skillsView.noMatchingSkills',
    defaultMessage: 'No matching skills found',
  },
  adjustSearchTerms: {
    id: 'skillsView.adjustSearchTerms',
    defaultMessage: 'Try adjusting your search terms',
  },
  skillsTitle: {
    id: 'skillsView.skillsTitle',
    defaultMessage: 'Skills',
  },
  addSkill: {
    id: 'skillsView.addSkill',
    defaultMessage: 'Add Skill',
  },
  skillsDescription: {
    id: 'skillsView.skillsDescription',
    defaultMessage:
      'View installed skills that extend Genius Assistant capabilities. {shortcut} to search.',
  },
  searchSkillsPlaceholder: {
    id: 'skillsView.searchSkillsPlaceholder',
    defaultMessage: 'Search skills...',
  },
  comingSoon: {
    id: 'skillsView.comingSoon',
    defaultMessage: 'Coming soon',
  },
  createTitle: {
    id: 'skillsView.createTitle',
    defaultMessage: 'Create a Skill',
  },
  createIntro: {
    id: 'skillsView.createIntro',
    defaultMessage:
      'A skill teaches Genius Assistant how to do a recurring task. Give it a name, say when to use it, and write the steps in plain language.',
  },
  fieldName: {
    id: 'skillsView.fieldName',
    defaultMessage: 'Name',
  },
  fieldNamePlaceholder: {
    id: 'skillsView.fieldNamePlaceholder',
    defaultMessage: 'e.g. Weekly report',
  },
  fieldNameSavedAs: {
    id: 'skillsView.fieldNameSavedAs',
    defaultMessage: 'Saved as: {slug}',
  },
  fieldWhen: {
    id: 'skillsView.fieldWhen',
    defaultMessage: 'When to use it',
  },
  fieldWhenPlaceholder: {
    id: 'skillsView.fieldWhenPlaceholder',
    defaultMessage: 'e.g. When I ask for the weekly sales report',
  },
  fieldInstructions: {
    id: 'skillsView.fieldInstructions',
    defaultMessage: 'Instructions',
  },
  fieldInstructionsPlaceholder: {
    id: 'skillsView.fieldInstructionsPlaceholder',
    defaultMessage:
      'Write the steps, one per line. Example:\n1. Open the sales spreadsheet\n2. Sum totals by region\n3. Write a short summary with the top 3 regions',
  },
  cancel: {
    id: 'skillsView.cancel',
    defaultMessage: 'Cancel',
  },
  save: {
    id: 'skillsView.save',
    defaultMessage: 'Save Skill',
  },
  saving: {
    id: 'skillsView.saving',
    defaultMessage: 'Saving...',
  },
  createdTitle: {
    id: 'skillsView.createdTitle',
    defaultMessage: 'Skill saved',
  },
  createdMsg: {
    id: 'skillsView.createdMsg',
    defaultMessage: '"{name}" is now available.',
  },
  createFailed: {
    id: 'skillsView.createFailed',
    defaultMessage: 'Could not save the skill',
  },
  editTitle: {
    id: 'skillsView.editTitle',
    defaultMessage: 'Edit Skill',
  },
  editIntro: {
    id: 'skillsView.editIntro',
    defaultMessage: 'Update when to use this skill and its instructions.',
  },
  fieldNameReadonlyHint: {
    id: 'skillsView.fieldNameReadonlyHint',
    defaultMessage: "The name can't be changed after a skill is created.",
  },
  saveChanges: {
    id: 'skillsView.saveChanges',
    defaultMessage: 'Save Changes',
  },
  updatedTitle: {
    id: 'skillsView.updatedTitle',
    defaultMessage: 'Skill updated',
  },
  updatedMsg: {
    id: 'skillsView.updatedMsg',
    defaultMessage: '"{name}" has been updated.',
  },
  updateFailed: {
    id: 'skillsView.updateFailed',
    defaultMessage: 'Could not update the skill',
  },
  readOnlySkill: {
    id: 'skillsView.readOnlySkill',
    defaultMessage: 'Read-only',
  },
  deleteSkill: {
    id: 'skillsView.deleteSkill',
    defaultMessage: 'Delete',
  },
  deleteConfirm: {
    id: 'skillsView.deleteConfirm',
    defaultMessage: 'Delete this skill? This cannot be undone.',
  },
  deleting: {
    id: 'skillsView.deleting',
    defaultMessage: 'Deleting...',
  },
  deletedTitle: {
    id: 'skillsView.deletedTitle',
    defaultMessage: 'Skill deleted',
  },
  deletedMsg: {
    id: 'skillsView.deletedMsg',
    defaultMessage: '"{name}" has been removed.',
  },
  deleteFailed: {
    id: 'skillsView.deleteFailed',
    defaultMessage: 'Could not delete the skill',
  },
});

function SkillItem({ skill, onClick }: { skill: SourceEntry; onClick: () => void }) {
  const intl = useIntl();
  const isEditable = skill.writable !== false;
  return (
    <Card
      onClick={onClick}
      className={`py-2 px-4 mb-2 bg-background-primary border-none transition-all duration-150 ${
        isEditable ? 'hover:bg-background-secondary cursor-pointer' : 'opacity-80'
      }`}
    >
      <div className="flex justify-between items-center gap-4">
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2 mb-1">
            <h3 className="text-base truncate">{skill.name}</h3>
          </div>
          <p className="text-text-secondary text-sm line-clamp-2">{skill.description}</p>
        </div>
        {!isEditable && (
          <Lock
            className="w-3.5 h-3.5 text-text-secondary shrink-0"
            aria-label={intl.formatMessage(i18n.readOnlySkill)}
          />
        )}
      </div>
    </Card>
  );
}

function SkillFormModal({
  open,
  onOpenChange,
  onSaved,
  skill,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSaved: () => void;
  skill?: SourceEntry | null;
}) {
  const intl = useIntl();
  const isEdit = Boolean(skill);
  const [title, setTitle] = useState('');
  const [when, setWhen] = useState('');
  const [instructions, setInstructions] = useState('');
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    if (open) {
      setTitle(skill?.name ?? '');
      setWhen(skill?.description ?? '');
      setInstructions(skill?.content ?? '');
    }
  }, [open, skill]);

  const slug = isEdit ? (skill?.name ?? '') : skillNameFromTitle(title);
  const canSave = slug.length > 0 && when.trim().length > 0 && instructions.trim().length > 0;
  const busy = saving || deleting;

  const handleSave = async () => {
    if (!canSave || busy) return;
    setSaving(true);
    try {
      const source =
        isEdit && skill
          ? await updateGlobalSkill(skill.path, skill.name, when.trim(), instructions.trim())
          : await createGlobalSkill(slug, when.trim(), instructions.trim());
      toastSuccess({
        title: intl.formatMessage(isEdit ? i18n.updatedTitle : i18n.createdTitle),
        msg: intl.formatMessage(isEdit ? i18n.updatedMsg : i18n.createdMsg, {
          name: source.name,
        }),
      });
      onOpenChange(false);
      onSaved();
    } catch (err) {
      toastError({
        title: intl.formatMessage(isEdit ? i18n.updateFailed : i18n.createFailed),
        msg: errorMessage(err, isEdit ? 'Failed to update skill' : 'Failed to create skill'),
      });
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async () => {
    if (!skill || busy) return;
    if (!window.confirm(intl.formatMessage(i18n.deleteConfirm))) return;
    setDeleting(true);
    try {
      await deleteGlobalSkill(skill.path);
      toastSuccess({
        title: intl.formatMessage(i18n.deletedTitle),
        msg: intl.formatMessage(i18n.deletedMsg, { name: skill.name }),
      });
      onOpenChange(false);
      onSaved();
    } catch (err) {
      toastError({
        title: intl.formatMessage(i18n.deleteFailed),
        msg: errorMessage(err, 'Failed to delete skill'),
      });
    } finally {
      setDeleting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[560px]">
        <DialogHeader>
          <DialogTitle>
            {intl.formatMessage(isEdit ? i18n.editTitle : i18n.createTitle)}
          </DialogTitle>
        </DialogHeader>
        <p className="text-sm text-text-secondary">
          {intl.formatMessage(isEdit ? i18n.editIntro : i18n.createIntro)}
        </p>
        <div className="space-y-4 mt-2">
          <div className="space-y-1">
            <label htmlFor="skill-name" className="text-text-primary text-xs">
              {intl.formatMessage(i18n.fieldName)}
            </label>
            <Input
              id="skill-name"
              value={isEdit ? slug : title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder={intl.formatMessage(i18n.fieldNamePlaceholder)}
              disabled={isEdit}
            />
            {isEdit ? (
              <p className="text-xs text-text-secondary">
                {intl.formatMessage(i18n.fieldNameReadonlyHint)}
              </p>
            ) : (
              slug && (
                <p className="text-xs text-text-secondary">
                  {intl.formatMessage(i18n.fieldNameSavedAs, { slug })}
                </p>
              )
            )}
          </div>
          <div className="space-y-1">
            <label htmlFor="skill-when" className="text-text-primary text-xs">
              {intl.formatMessage(i18n.fieldWhen)}
            </label>
            <Input
              id="skill-when"
              value={when}
              onChange={(e) => setWhen(e.target.value)}
              placeholder={intl.formatMessage(i18n.fieldWhenPlaceholder)}
            />
          </div>
          <div className="space-y-1">
            <label htmlFor="skill-instructions" className="text-text-primary text-xs">
              {intl.formatMessage(i18n.fieldInstructions)}
            </label>
            <textarea
              id="skill-instructions"
              value={instructions}
              onChange={(e) => setInstructions(e.target.value)}
              placeholder={intl.formatMessage(i18n.fieldInstructionsPlaceholder)}
              rows={7}
              className="w-full rounded-md border focus:border-border-secondary hover:border-border-secondary bg-background-primary px-3 py-2 text-sm text-text-primary placeholder:text-text-secondary placeholder:font-light focus-visible:outline-none disabled:cursor-not-allowed disabled:opacity-50"
            />
          </div>
        </div>
        <DialogFooter className={isEdit ? 'sm:justify-between' : undefined}>
          {isEdit && (
            <Button
              variant="ghost"
              onClick={handleDelete}
              disabled={busy}
              className="text-red-500 hover:text-red-600 hover:bg-red-500/10 flex items-center gap-1.5"
            >
              <Trash2 className="w-4 h-4" />
              {deleting ? intl.formatMessage(i18n.deleting) : intl.formatMessage(i18n.deleteSkill)}
            </Button>
          )}
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)} disabled={busy}>
              {intl.formatMessage(i18n.cancel)}
            </Button>
            <Button onClick={handleSave} disabled={!canSave || busy}>
              {saving
                ? intl.formatMessage(i18n.saving)
                : intl.formatMessage(isEdit ? i18n.saveChanges : i18n.save)}
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function SkillSkeleton() {
  return (
    <Card className="p-2 mb-2 bg-background-primary">
      <div className="flex justify-between items-start gap-4">
        <div className="min-w-0 flex-1">
          <Skeleton className="h-5 w-3/4 mb-2" />
          <Skeleton className="h-4 w-full" />
        </div>
      </div>
    </Card>
  );
}

export default function SkillsView() {
  const intl = useIntl();
  const [skills, setSkills] = useState<SourceEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [showSkeleton, setShowSkeleton] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showContent, setShowContent] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [editingSkill, setEditingSkill] = useState<SourceEntry | null>(null);

  const filteredSkills = useMemo(() => {
    if (!searchTerm) return skills;
    const searchLower = searchTerm.toLowerCase();
    return skills.filter(
      (skill) =>
        skill.name.toLowerCase().includes(searchLower) ||
        skill.description.toLowerCase().includes(searchLower)
    );
  }, [skills, searchTerm]);

  const loadSkills = useCallback(async () => {
    try {
      setLoading(true);
      setShowSkeleton(true);
      setShowContent(false);
      setError(null);
      const sources = await listSkillSources(getInitialWorkingDir());
      setSkills(sources);
    } catch (err) {
      setError(errorMessage(err, 'Failed to load skills'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadSkills();
  }, [loadSkills]);

  useEffect(() => {
    if (!loading && showSkeleton) {
      const timer = setTimeout(() => {
        setShowSkeleton(false);
        setTimeout(() => setShowContent(true), 50);
      }, 300);
      return () => clearTimeout(timer);
    }
    return undefined;
  }, [loading, showSkeleton]);

  const renderContent = () => {
    if (loading || showSkeleton) {
      return (
        <div className="space-y-2">
          <SkillSkeleton />
          <SkillSkeleton />
          <SkillSkeleton />
        </div>
      );
    }

    if (error) {
      return (
        <div className="flex flex-col items-center justify-center h-full text-text-secondary">
          <AlertCircle className="h-12 w-12 text-red-500 mb-4" />
          <p className="text-lg mb-2">{intl.formatMessage(i18n.errorLoadingSkills)}</p>
          <p className="text-sm text-center mb-4">{error}</p>
          <Button onClick={loadSkills} variant="default">
            {intl.formatMessage(i18n.tryAgain)}
          </Button>
        </div>
      );
    }

    if (skills.length === 0) {
      return (
        <div className="flex flex-col justify-center pt-2 h-full">
          <p className="text-lg">{intl.formatMessage(i18n.noSkillsInstalled)}</p>
          <p className="text-sm text-text-secondary">
            {intl.formatMessage(i18n.noSkillsDescription)}
          </p>
        </div>
      );
    }

    if (filteredSkills.length === 0 && searchTerm) {
      return (
        <div className="flex flex-col items-center justify-center h-full text-text-secondary mt-4">
          <Zap className="h-12 w-12 mb-4" />
          <p className="text-lg mb-2">{intl.formatMessage(i18n.noMatchingSkills)}</p>
          <p className="text-sm">{intl.formatMessage(i18n.adjustSearchTerms)}</p>
        </div>
      );
    }

    return (
      <div className="space-y-2">
        {filteredSkills.map((skill) => (
          <SkillItem
            key={skill.path}
            skill={skill}
            onClick={() => {
              if (skill.writable !== false) setEditingSkill(skill);
            }}
          />
        ))}
      </div>
    );
  };

  return (
    <MainPanelLayout>
      <div className="flex-1 flex flex-col min-h-0">
        <div className="bg-background-primary px-8 pb-8 pt-16">
          <div className="flex flex-col page-transition">
            <div className="flex justify-between items-center mb-1">
              <h1 className="text-4xl font-light">{intl.formatMessage(i18n.skillsTitle)}</h1>
              <Button
                variant="outline"
                size="sm"
                className="flex items-center gap-2"
                onClick={() => setShowCreateModal(true)}
              >
                <Plus className="w-4 h-4" />
                {intl.formatMessage(i18n.addSkill)}
              </Button>
            </div>
            <p className="text-sm text-text-secondary mb-1">
              {intl.formatMessage(i18n.skillsDescription, {
                shortcut: getSearchShortcutText(),
              })}
            </p>
          </div>
        </div>

        <div className="flex-1 min-h-0 relative px-8">
          <ScrollArea className="h-full">
            <SearchView
              onSearch={(term) => setSearchTerm(term)}
              placeholder={intl.formatMessage(i18n.searchSkillsPlaceholder)}
            >
              <div
                className={`h-full relative transition-all duration-300 ${
                  showContent || showSkeleton ? 'opacity-100 animate-in fade-in' : 'opacity-0'
                }`}
              >
                {renderContent()}
              </div>
            </SearchView>
          </ScrollArea>
        </div>
      </div>
      <SkillFormModal
        open={showCreateModal}
        onOpenChange={setShowCreateModal}
        onSaved={loadSkills}
      />
      <SkillFormModal
        open={Boolean(editingSkill)}
        onOpenChange={(open) => {
          if (!open) setEditingSkill(null);
        }}
        onSaved={loadSkills}
        skill={editingSkill}
      />
    </MainPanelLayout>
  );
}
