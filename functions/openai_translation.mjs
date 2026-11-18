import {requestBody} from './translation_provider.mjs';

export const openaiTranslationModel = 'gpt-6-luna';

export async function translateWithOpenAI(input, {apiKey, fetcher = fetch} = {}) {
  const {messages, max_tokens, reasoning} = requestBody({...input, model: 'openai/gpt-6-luna'});
  if (typeof apiKey !== 'string' || !apiKey.trim()) throw Error('openai_translation_key_missing');

  const start = Date.now();
  let response;
  try {
    response = await fetcher('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: {Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json'},
      body: JSON.stringify({
        model: openaiTranslationModel,
        instructions: messages[0].content,
        input: messages[1].content,
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
    translation,
    actualModel: result.model,
    inputTokens: result.usage?.input_tokens ?? null,
    outputTokens: result.usage?.output_tokens ?? null,
    reasoningTokens: result.usage?.output_tokens_details?.reasoning_tokens ?? null,
    // Estimate at standard GPT-6 Luna rates, without cached-input discounts.
    costUsd: ((result.usage?.input_tokens ?? 0) * 0.10 + (result.usage?.output_tokens ?? 0) * 0.50) / 1_000_000,
    latencyMs: Date.now() - start,
  };
}
