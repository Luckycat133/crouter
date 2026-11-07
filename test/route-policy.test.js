'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {surfaceCandidates} = require('../lib/route-build.js');
function fixture(values) {
  const names = ['CR_MODEL','CR_MODEL_OPUS','CR_MODEL_SONNET','CR_MODEL_HAIKU','CR_MODEL_SUBAGENT','CR_PLAN_URL','CR_PLAN_TYPE','CR_PLAN_TOKENS','CR_PLAN_MODEL','CR_PLAN_MODEL_OPUS','CR_PLAN_MODEL_SONNET','CR_PLAN_MODEL_HAIKU','CR_PLAN_MODEL_SUBAGENT','CR_API_URL','CR_API_TYPE','CR_API_TOKENS','CR_API_MODEL','CR_API_MODEL_OPUS','CR_API_MODEL_SONNET','CR_API_MODEL_HAIKU','CR_API_MODEL_SUBAGENT','CROUTER_ALLOW_PAID_FALLBACK','CROUTER_ALLOW_CROSS_MODEL_FALLBACK'];
  const old = {...process.env};
  for (const k of names) delete process.env[k];
  Object.assign(process.env, {CR_MODEL:'model', CR_PLAN_URL:'https://plan.invalid', CR_PLAN_TOKENS:'test-plan-1 test-plan-2', CR_PLAN_MODEL:'upstream', CR_API_URL:'https://api.invalid', CR_API_TOKENS:'test-api', CR_API_MODEL:'upstream'}, values);
  try { return surfaceCandidates(); } finally { for (const k of names) { if (old[k] === undefined) delete process.env[k]; else process.env[k]=old[k]; } }
}
test('plan keys do not silently fall back to paid API', () => assert.equal(fixture({}).length, 2));
test('explicit paid authorization admits only same-model API', () => assert.equal(fixture({CROUTER_ALLOW_PAID_FALLBACK:'1'}).length, 3));
test('fee authorization is not model-substitution authorization', () => assert.equal(fixture({CROUTER_ALLOW_PAID_FALLBACK:'1', CR_API_MODEL:'different'}).length, 2));
test('both independent opt-ins are needed for cross-model paid fallback', () => assert.equal(fixture({CROUTER_ALLOW_PAID_FALLBACK:'1', CROUTER_ALLOW_CROSS_MODEL_FALLBACK:'1', CR_API_MODEL:'different'}).length, 3));
test('API-only setup remains usable', () => { const c=fixture({CR_PLAN_TOKENS:''}); assert.equal(c.length,1); assert.equal(c[0].label,'api-key-1'); });
