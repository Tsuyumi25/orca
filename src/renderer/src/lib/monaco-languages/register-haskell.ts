import type * as Monaco from 'monaco-editor'
import type { IRawGrammar } from 'vscode-textmate'
import { registerTextMateLanguage } from './textmate-language-registration'

type MonacoModule = typeof Monaco

export const HASKELL_LANGUAGE_ID = 'haskell'
export const HASKELL_TEXTMATE_SCOPE = 'source.haskell'

export const haskellLanguageConfiguration: Monaco.languages.LanguageConfiguration = {
  comments: {
    lineComment: '--',
    blockComment: ['{-', '-}']
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

export async function loadHaskellTextMateGrammar(scopeName: string): Promise<IRawGrammar | null> {
  if (scopeName !== HASKELL_TEXTMATE_SCOPE) {
    return null
  }

  // Why: Haskell highlighting uses the maintained VS Code TextMate grammar
  // from octref/language-haskell (BSD-3-Clause; see textmate-grammars/
  // haskell-LICENSE.txt).
  const grammarModule = await import('./textmate-grammars/haskell.tmLanguage.json')
  return grammarModule.default as unknown as IRawGrammar
}

export function registerHaskellLanguage(monaco: MonacoModule): void {
  registerTextMateLanguage(monaco, {
    language: {
      id: HASKELL_LANGUAGE_ID,
      extensions: ['.hs', '.hs-boot', '.hsig'],
      aliases: ['Haskell', 'haskell']
    },
    configuration: haskellLanguageConfiguration,
    scopeName: HASKELL_TEXTMATE_SCOPE,
    loadGrammar: loadHaskellTextMateGrammar
  })
}
