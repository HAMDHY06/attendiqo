import test from 'node:test'; import assert from 'node:assert/strict';
import { processSmsOutbox } from '../lib/sms_delivery_worker.mjs'; import { MockSmsProvider } from '../lib/sms_provider.mjs';
const item={messageId:'m',protectedPhone:'+94771234567',recipientPhoneHash:'h',body:'safe'};
test('mock SMS worker sends without logging phone or body', async()=>{const logs=[];const records=[];const value=await processSmsOutbox({listPending:async()=>[item],claim:async()=>true,provider:new MockSmsProvider(),record:async x=>records.push(x),updateOutbox:async()=>{},logger:x=>logs.push(x)});assert.equal(value.sent,1);assert.equal(JSON.stringify(logs).includes('9477'),false);assert.equal(records.length,1);});
test('dry run makes no writes', async()=>{let writes=0;await processSmsOutbox({listPending:async()=>[item],claim:async()=>true,provider:new MockSmsProvider(),record:async()=>writes++,updateOutbox:async()=>writes++,dryRun:true});assert.equal(writes,0);});
