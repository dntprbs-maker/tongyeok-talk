import {createHash} from 'node:crypto';

function digest(value) {
  return createHash('sha256').update(JSON.stringify(value)).digest('hex');
}

export function dictionaryKey({text, source, target}) {
  return digest([source, target, text.normalize('NFC').trim()]);
}

const segmenter = new Intl.Segmenter(['ko', 'mn'], {granularity: 'sentence'});

function splitSentences(text) {
  // Abbreviations, addresses, ellipses, and quoted sentences can have
  // ambiguous boundaries. Preserve their context in one translation.
  if (/[@]|:\/\/|\bwww\.|\.{2,}|[…"“”«»]|[\p{Script=Latin}]\.|\p{Lu}\./u.test(text)) return [];
  const parts = Array.from(segmenter.segment(text), ({segment}) => segment);
  if (parts.length < 2 || parts.some(part => !/\p{L}/u.test(part))) return [];
  // Do not cut after a bare number or at a line break without punctuation.
  if (parts.slice(0, -1).some(part => !/[.!?。！？]$/u.test(part.trim()) ||
      /\d\.$/u.test(part.trim()))) return [];
  return parts;
}

function approved(snapshot) {
  const entry = snapshot.data();
  return entry?.approved && typeof entry.translation === 'string' && entry.translation.trim()
    ? entry.translation.trim() : null;
}

export function dictionaryProvider(db, messageRef, provider, batchProvider) {
  const dictionary = db.collection('_groupTranslationDictionary');
  const entryFor = input => dictionary.doc(dictionaryKey(input));
  const fromDictionary = translation => ({translation, actualModel: 'dictionary', costUsd: 0});

  async function count(entry, translation) {
    const receipt = entry.collection('occurrences').doc(digest(messageRef.path));
    await db.runTransaction(async transaction => {
      const [current, occurrence] = await transaction.getAll(entry, receipt);
      if (current.data()?.approved || occurrence.exists) return;
      const count = (current.data()?.count ?? 0) + 1;
      transaction.create(receipt, {});
      transaction.set(entry, count < 10 ? {count} : {
        count, translation, provenance: 'repeated', approved: true,
      });
    }).catch(error => {
      console.error('translation_dictionary_count_failed', error.code);
    });
  }

  return async input => {
    const whole = entryFor(input);
    const parts = batchProvider ? splitSentences(input.text) : [];
    if (!parts.length) {
      const known = approved(await whole.get());
      if (known) return fromDictionary(known);
      const result = await provider(input);
      await count(whole, result.translation);
      return result;
    }

    const entries = new Map();
    const sentences = parts.map(part => {
      const text = part.trim();
      const ref = entryFor({...input, text});
      if (!entries.has(ref.id)) entries.set(ref.id, {text, ref, translation: null});
      return entries.get(ref.id);
    });
    const [wholeSnapshot, ...snapshots] = await db.getAll(
      whole, ...Array.from(entries.values(), ({ref}) => ref),
    );
    const known = approved(wholeSnapshot);
    if (known) return fromDictionary(known);
    for (const snapshot of snapshots) entries.get(snapshot.id).translation = approved(snapshot);

    const missing = Array.from(entries.values()).filter(sentence => !sentence.translation);
    let metadata = fromDictionary('');
    if (missing.length === 1) {
      metadata = await provider({...input, text: missing[0].text});
      missing[0].translation = metadata.translation;
    } else if (missing.length > 1) {
      const {translations, ...result} = await batchProvider(
        input, missing.map(({text}) => text),
      );
      if (!Array.isArray(translations) || translations.length !== missing.length ||
          translations.some(value => typeof value !== 'string' || !value.trim())) {
        throw Error('invalid_translation_batch');
      }
      metadata = result;
      missing.forEach((sentence, index) => { sentence.translation = translations[index]; });
    }
    await Promise.all(missing.map(({ref, translation}) => count(ref, translation)));
    const translation = parts.map((part, index) => {
      const leading = part.match(/^\s*/u)[0];
      const trailing = part.match(/\s*$/u)[0];
      return leading + sentences[index].translation.trim() + trailing;
    }).join('').trim();
    return {...metadata, translation};
  };
}
