/*
 * logic/CredentialCodec.ets 的回归用例（P0-10 凭据加密）。
 *
 * 直接运行：node entry/src/test/run.mjs
 *
 * 背景：配对凭据（含 accessToken / refreshToken）早期以**明文**存进 preferences。
 * 改为 HUKS 加密后，密文的存储格式需要版本前缀并支持旧数据迁移，
 * 这些是纯字符串运算，必须能在不进设备的情况下验证。
 *
 * HUKS 本身只能在真机/模拟器跑，因此这里只测格式与迁移判定：
 * 若这里错了，轻则老用户升级后丢凭据，重则明文一直留在设备上。
 */
import assert from 'node:assert/strict';
import {
  CIPHER_VERSION, isEncryptedPayload, isLegacyPlaintext, packCipher, unpackCipher
} from '../main/ets/logic/CredentialCodec.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

test('打包结果带版本前缀，可被识别为密文', () => {
  const packed = packCipher('aXY=', 'ZGF0YQ==');
  assert.equal(packed, `${CIPHER_VERSION}:aXY=:ZGF0YQ==`);
  assert.equal(isEncryptedPayload(packed), true);
});

test('打包/解包可往返', () => {
  const unpacked = unpackCipher(packCipher('aXY=', 'ZGF0YQ=='));
  assert.notEqual(unpacked, undefined);
  assert.equal(unpacked.ivBase64, 'aXY=');
  assert.equal(unpacked.dataBase64, 'ZGF0YQ==');
});

test('空 IV 或空密文时拒绝打包（不产生坏数据）', () => {
  assert.throws(() => packCipher('', 'ZGF0YQ=='));
  assert.throws(() => packCipher('aXY=', ''));
});

test('旧版明文 JSON 被识别为明文而不是密文', () => {
  const legacy = '{"serverUrl":"https://host","session":{"accessToken":"token"}}';
  assert.equal(isLegacyPlaintext(legacy), true);
  assert.equal(isEncryptedPayload(legacy), false);
});

test('密文不会被误判成旧版明文', () => {
  assert.equal(isLegacyPlaintext(packCipher('aXY=', 'ZGF0YQ==')), false);
});

test('旧明文带空白也能认出（升级前可能被格式化过）', () => {
  assert.equal(isLegacyPlaintext('  \n {"serverUrl":"x"}  '), true);
});

test('未知版本前缀不当作本工程密文', () => {
  assert.equal(isEncryptedPayload('v2:a:b'), false);
  assert.equal(isLegacyPlaintext('v2:a:b'), false);
});

test('字段缺失的密文被判为不合法', () => {
  assert.equal(isEncryptedPayload(`${CIPHER_VERSION}:`), false);
  assert.equal(isEncryptedPayload(`${CIPHER_VERSION}:only-iv`), false);
  assert.equal(isEncryptedPayload(`${CIPHER_VERSION}:a:b:c`), false);
});

test('非法格式解包返回 undefined（调用方按「无法解密」处理）', () => {
  assert.equal(unpackCipher('不是密文'), undefined);
  assert.equal(unpackCipher(`${CIPHER_VERSION}:`), undefined);
});

test('普通文本既不是密文也不是旧明文', () => {
  assert.equal(isEncryptedPayload('随便一段文本'), false);
  assert.equal(isLegacyPlaintext('随便一段文本'), false);
});

// ---- 运行器 ----
const passed = [];
const failed = [];
for (const { name, fn } of tests) {
  try {
    fn();
    passed.push(name);
    console.log(`  ✓ ${name}`);
  } catch (error) {
    failed.push(name);
    console.log(`  ✗ ${name}`);
    console.log(`     ${error.message}`);
  }
}
console.log(`\n${passed.length} passed / ${failed.length} failed`);
if (failed.length > 0) process.exitCode = 1;
export { tests };
