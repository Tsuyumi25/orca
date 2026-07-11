import type * as Monaco from 'monaco-editor'
import type { IRawGrammar } from 'vscode-textmate'
import { registerTextMateLanguage } from './textmate-language-registration'

type MonacoModule = typeof Monaco

export const NIX_LANGUAGE_ID = 'nix'
export const NIX_TEXTMATE_SCOPE = 'source.nix'

export const nixLanguageConfiguration: Monaco.languages.LanguageConfiguration = {
  comments: {
    lineComment: '#',
    blockComment: ['/*', '*/']
  },
  brackets: [
    ['{', '}'],
    ['[', ']'],
    ['(', ')']
  ],
  autoClosingPairs: [
    { open: '{', close: '}' },
    { open: '[', close: ']' },
    { open: '(', close: ')' },
    { open: '"', close: '"' }
  ],
  surroundingPairs: [
    { open: '{', close: '}' },
    { open: '[', close: ']' },
    { open: '(', close: ')' },
    { open: '"', close: '"' }
  ]
}

export async function loadNixTextMateGrammar(scopeName: string): Promise<IRawGrammar | null> {
  if (scopeName !== NIX_TEXTMATE_SCOPE) {
    return null
  }

  // Why: Nix highlighting uses the maintained VS Code TextMate grammar from
  // nix-community/vscode-nix-ide (MIT; see textmate-grammars/nix-LICENSE.txt).
  const grammarModule = await import('./textmate-grammars/nix.tmLanguage.json')
  return grammarModule.default as unknown as IRawGrammar
}

export function registerNixLanguage(monaco: MonacoModule): void {
  registerTextMateLanguage(monaco, {
    language: {
      id: NIX_LANGUAGE_ID,
      extensions: ['.nix'],
      aliases: ['Nix', 'nix']
    },
    configuration: nixLanguageConfiguration,
    scopeName: NIX_TEXTMATE_SCOPE,
    loadGrammar: loadNixTextMateGrammar
  })
}
