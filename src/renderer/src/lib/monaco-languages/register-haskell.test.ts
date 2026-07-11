import { describe, expect, it, vi } from 'vitest'
import {
  HASKELL_LANGUAGE_ID,
  HASKELL_TEXTMATE_SCOPE,
  haskellLanguageConfiguration,
  loadHaskellTextMateGrammar,
  registerHaskellLanguage
} from './register-haskell'

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

describe('registerHaskellLanguage', () => {
  it('maps Haskell extensions to the reusable TextMate-backed language registration', () => {
    const monaco = createMonacoMock()

    registerHaskellLanguage(monaco as never)

    expect(monaco.languages.register).toHaveBeenCalledWith({
      id: HASKELL_LANGUAGE_ID,
      extensions: ['.hs', '.hs-boot', '.hsig'],
      aliases: ['Haskell', 'haskell']
    })
    expect(monaco.languages.setLanguageConfiguration).toHaveBeenCalledWith(
      HASKELL_LANGUAGE_ID,
      haskellLanguageConfiguration
    )
    expect(monaco.languages.registerTokensProviderFactory).toHaveBeenCalledWith(
      HASKELL_LANGUAGE_ID,
      expect.objectContaining({ create: expect.any(Function) })
    )
  })
})

describe('loadHaskellTextMateGrammar', () => {
  it('loads the vendored Haskell TextMate grammar for the Haskell scope', async () => {
    const grammar = await loadHaskellTextMateGrammar(HASKELL_TEXTMATE_SCOPE)

    expect(grammar).toMatchObject({
      name: 'Haskell',
      scopeName: HASKELL_TEXTMATE_SCOPE,
      fileTypes: ['hs', 'hs-boot', 'hsig']
    })
  })

  it('ignores unrelated TextMate scopes', async () => {
    await expect(loadHaskellTextMateGrammar('source.python')).resolves.toBeNull()
  })
})
