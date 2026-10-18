/*
 * logic/Attachments.ets 的回归用例（P3-1 附件）。
 *
 * 规则来源：宿主 `src/mobile/adapter.js`
 * - 图片 ≤ 10 MiB，其它 ≤ 20 MiB；
 * - 图片类型白名单 png/jpeg/webp/gif；
 * - 单条消息最多 8 个附件。
 *
 * 这些限制错了会直接被主机 413/415 拒绝，而且提示对用户没意义，
 * 所以必须在选择阶段就拦下。
 *
 * 直接运行：node entry/src/test/run.mjs
 */
import assert from 'node:assert/strict';
import {
  addBlockedReason, allUploaded, attachmentProblem, baseName, canAddMore, filesOf,
  fitImageSize, formatSize, imagesOf, isImageType, limitFor, limitLabel, MAX_ATTACHMENTS,
  MAX_FILE_BYTES, MAX_IMAGE_BYTES, mediaTypeOf, uploadingCount
} from '../main/ets/logic/Attachments.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

test('图片类型白名单', () => {
  assert.equal(isImageType('image/png'), true);
  assert.equal(isImageType('image/JPEG'), true); // 大小写不敏感
  assert.equal(isImageType('image/svg+xml'), false);
  assert.equal(isImageType('application/pdf'), false);
});

test('上限按类型区分', () => {
  assert.equal(limitFor('image/png'), MAX_IMAGE_BYTES);
  assert.equal(limitFor('application/pdf'), MAX_FILE_BYTES);
  assert.equal(MAX_IMAGE_BYTES, 10 * 1024 * 1024);
  assert.equal(MAX_FILE_BYTES, 20 * 1024 * 1024);
});

test('体积格式化', () => {
  assert.equal(formatSize(0), '0 B');
  assert.equal(formatSize(900), '900 B');
  assert.equal(formatSize(2048), '2 KB');
  assert.equal(formatSize(5 * 1024 * 1024), '5.0 MB');
});

test('上限文案', () => {
  assert.equal(limitLabel('image/png'), '10 MB');
  assert.equal(limitLabel('application/pdf'), '20 MB');
});

test('校验：空文件/空名/超限', () => {
  assert.equal(attachmentProblem('', 'image/png', 100), '文件名不能为空');
  assert.equal(attachmentProblem('a.png', 'image/png', 0), '文件是空的');
  const big = attachmentProblem('a.png', 'image/png', MAX_IMAGE_BYTES + 1);
  assert.equal(big.includes('10 MB'), true);
  assert.equal(big.includes('图片'), true);
});

test('校验：图片 10MB 边缘与文件 20MB 边缘', () => {
  assert.equal(attachmentProblem('a.png', 'image/png', MAX_IMAGE_BYTES), '');
  assert.equal(attachmentProblem('a.png', 'image/png', MAX_IMAGE_BYTES + 1) === '', false);
  assert.equal(attachmentProblem('a.pdf', 'application/pdf', MAX_FILE_BYTES), '');
  assert.equal(attachmentProblem('a.pdf', 'application/pdf', MAX_FILE_BYTES + 1) === '', false);
});

test('最多 8 个附件', () => {
  const seven = new Array(7).fill({ key: 'k', name: 'a', mediaType: 'image/png', size: 1 });
  assert.equal(canAddMore(seven), true);
  assert.equal(addBlockedReason(seven), '');
  const eight = new Array(MAX_ATTACHMENTS).fill({ key: 'k', name: 'a', mediaType: 'image/png', size: 1 });
  assert.equal(canAddMore(eight), false);
  assert.equal(addBlockedReason(eight).includes('8'), true);
});

test('全部上传成功才能发', () => {
  assert.equal(allUploaded([]), true);
  assert.equal(allUploaded([{ key: 'a', name: 'a', mediaType: 'image/png', size: 1 }]), false);
  assert.equal(allUploaded([{ key: 'a', name: 'a', mediaType: 'image/png', size: 1, receiptId: 'r1' }]), true);
  assert.equal(allUploaded([{ key: 'a', name: 'a', mediaType: 'image/png', size: 1, receiptId: 'r1', error: 'x' }]), false);
});

test('上传中计数', () => {
  assert.equal(uploadingCount([]), 0);
  assert.equal(uploadingCount([
    { key: 'a', name: 'a', mediaType: 'image/png', size: 1 },
    { key: 'b', name: 'b', mediaType: 'image/png', size: 1, receiptId: 'r' }
  ]), 1);
});

test('由文件名推断类型', () => {
  assert.equal(mediaTypeOf('a.PNG'), 'image/png');
  assert.equal(mediaTypeOf('a.jpeg'), 'image/jpeg');
  assert.equal(mediaTypeOf('a.webp'), 'image/webp');
  assert.equal(mediaTypeOf('a.gif'), 'image/gif');
  assert.equal(mediaTypeOf('a.pdf'), 'application/pdf');
  assert.equal(mediaTypeOf('a.md'), 'text/plain');
  assert.equal(mediaTypeOf('a.unknown'), 'application/octet-stream');
});

test('从 uri 取文件名', () => {
  assert.equal(baseName('file://media/Photo/1/a.jpg'), 'a.jpg');
  assert.equal(baseName('a.jpg?x=1'), 'a.jpg');
  assert.equal(baseName(''), 'file');
});

test('消息内图片/文件拆分', () => {
  // type 是字面量联合，直接写字面量会被推断成 string，需要显式标注
  const list = [
    { id: 'a', type: 'image' as const, name: 'a.png' },
    { id: 'b', type: 'file' as const, name: 'b.pdf' },
    { id: 'c', type: 'image' as const, name: 'c.jpg' }
  ];
  assert.equal(imagesOf(list).length, 2);
  assert.equal(filesOf(list).length, 1);
  assert.equal(imagesOf(undefined).length, 0);
  assert.equal(filesOf(undefined).length, 0);
});

test('图片展示尺寸：等比缩放不放大', () => {
  // 240x140 缩到 200 宽
  const small = fitImageSize(240, 140, 200, 320);
  assert.equal(small.width, 200);
  assert.equal(small.height, Math.round(140 * (200 / 240)));
  // 小图不放大
  const tiny = fitImageSize(50, 50, 200, 320);
  assert.equal(tiny.width, 50);
  assert.equal(tiny.height, 50);
});

test('图片展示尺寸：超高时受最大高度限制', () => {
  const tall = fitImageSize(200, 2000, 240, 320);
  assert.equal(tall.height, 320);
  assert.equal(tall.width <= 240, true);
});

test('图片展示尺寸：缺尺寸时按 4:3 占位', () => {
  const fallback = fitImageSize(undefined, undefined, 240, 320);
  assert.equal(fallback.width, 240);
  assert.equal(fallback.height, 180);
  const zero = fitImageSize(0, 0, 200, 320);
  assert.equal(zero.width, 200);
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
