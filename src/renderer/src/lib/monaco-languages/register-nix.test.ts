import { describe, expect, it, vi } from 'vitest'
import {
  NIX_LANGUAGE_ID,
  NIX_TEXTMATE_SCOPE,
  loadNixTextMateGrammar,
  nixLanguageConfiguration,
  registerNixLanguage
} from './register-nix'

function createMonacoMock() {
  return {
    languages: {
      getLanguages: vi.fn(() => []),
      register: vi.fn(),
      setLanguageConfiguration: vi.fn(),
      registerTokensProviderFactory: vi.fn()
    }
  }
}

describe('registerNixLanguage', () => {
  it('maps Nix extensions to the reusable TextMate-backed language registration', () => {
    const monaco = createMonacoMock()

    registerNixLanguage(monaco as never)

    expect(monaco.languages.register).toHaveBeenCalledWith({
      id: NIX_LANGUAGE_ID,
      extensions: ['.nix'],
      aliases: ['Nix', 'nix']
    })
    expect(monaco.languages.setLanguageConfiguration).toHaveBeenCalledWith(
      NIX_LANGUAGE_ID,
      nixLanguageConfiguration
    )
    expect(monaco.languages.registerTokensProviderFactory).toHaveBeenCalledWith(
      NIX_LANGUAGE_ID,
      expect.objectContaining({ create: expect.any(Function) })
    )
  })
})

describe('loadNixTextMateGrammar', () => {
  it('loads the vendored Nix TextMate grammar for the Nix scope', async () => {
    const grammar = await loadNixTextMateGrammar(NIX_TEXTMATE_SCOPE)

    expect(grammar).toMatchObject({
      name: 'Nix',
      scopeName: NIX_TEXTMATE_SCOPE,
      fileTypes: ['nix']
    })
  })

  it('ignores unrelated TextMate scopes', async () => {
    await expect(loadNixTextMateGrammar('source.python')).resolves.toBeNull()
  })
})
