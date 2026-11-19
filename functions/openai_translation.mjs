import {requestBody} from './translation_provider.mjs';

export const openaiTranslationModel = 'gpt-6-luna';

export async function translateWithOpenAI(input, {apiKey, fetcher = fetch, sentences} = {}) {
  const {messages, max_tokens, reasoning} = requestBody({...input, model: 'openai/gpt-6-luna'});
  if (typeof apiKey !== 'string' || !apiKey.trim()) throw Error('openai_translation_key_missing');

  const batch = sentences !== undefined;
  if (batch && (!Array.isArray(sentences) || sentences.length < 2 ||
      sentences.some(text => typeof text !== 'string' || !text.trim()) ||
      sentences.reduce((length, text) => length + [...text].length, 0) > 200)) {
    throw Error('invalid_translation_batch');
  }
  const segments = batch ? sentences.map((text, id) => ({id, text})) : null;
  const keys = segments?.map(({id}) => String(id));
  const instructions = batch
    ? messages[0].content.replace('Return only the translation, without commentary or quotes.',
      'Translate each segment independently. Return a JSON object keyed by the segment IDs, with a translation string for each ID.')
    : messages[0].content;
  const start = Date.now();
  let response;
  try {
    response = await fetcher('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: {Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json'},
      body: JSON.stringify({
        model: openaiTranslationModel,
        instructions,
        input: batch ? JSON.stringify(segments) : messages[1].content,
        ...(batch ? {text: {format: {
          type: 'json_schema', name: 'sentence_translations', strict: true,
          schema: {
            type: 'object',
            properties: Object.fromEntries(keys.map(key => [key, {type: 'string'}])),
            required: keys, additionalProperties: false,
          },
        }}} : {}),
        reasoning: {effort: reasoning.effort},
        max_output_tokens: max_tokens,
        store: false,
      }),
      signal: AbortSignal.timeout(45000),
    });
  } catch {
    throw Error('translation_network_error');
  }
  if (!response.ok) throw Error(`openai_translation_http_${response.status}`);

  let result;
  try { result = await response.json(); } catch { throw Error('invalid_provider_json'); }
  if (result?.status !== 'completed') throw Error('openai_translation_incomplete');
  if (result.model !== openaiTranslationModel) throw Error('unexpected_response_model');
  const translation = result.output?.filter(item => item.type === 'message' && item.role === 'assistant')
    .flatMap(item => item.content.filter(part => part.type === 'output_text').map(part => part.text))
    .join('').trim();
  if (!translation || translation.length > 12000) throw Error('invalid_translation_response');

  return {
    ...(batch ? {translations: parseBatch(translation, keys)} : {translation}),
    actualModel: result.model,
    inputTokens: result.usage?.input_tokens ?? null,
    outputTokens: result.usage?.output_tokens ?? null,
    reasoningTokens: result.usage?.output_tokens_details?.reasoning_tokens ?? null,
    // Estimate at standard GPT-6 Luna rates, without cached-input discounts.
    costUsd: ((result.usage?.input_tokens ?? 0) * 0.10 + (result.usage?.output_tokens ?? 0) * 0.50) / 1_000_000,
    latencyMs: Date.now() - start,
  };
}

function parseBatch(text, keys) {
  let result;
  try { result = JSON.parse(text); } catch { throw Error('invalid_translation_batch'); }
  if (!result || typeof result !== 'object' || Array.isArray(result) ||
      Object.keys(result).length !== keys.length ||
      keys.some(key => typeof result[key] !== 'string' || !result[key].trim())) {
    throw Error('invalid_translation_batch');
  }
  return keys.map(key => result[key].trim());
}
