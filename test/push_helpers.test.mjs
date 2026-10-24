import {test} from 'node:test';
import assert from 'node:assert/strict';
import {Timestamp} from '@google-cloud/firestore';
import {compareTimestamps} from '../tools/push_helpers.mjs';
test('real Node Firestore timestamps order exactly without compareTo',()=>{
 const a=new Timestamp(100,1),b=new Timestamp(100,2),c=new Timestamp(101,0);
 assert.equal(typeof a.compareTo,'undefined');
 assert.ok(compareTimestamps(a,b)<0);assert.ok(compareTimestamps(c,b)>0);assert.equal(compareTimestamps(a,a),0);
});
