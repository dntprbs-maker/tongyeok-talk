'use strict';

const param = new URLSearchParams(location.search);
const code = param.get('r') ?? '';
const mn = param.get('l') === 'mn';
const get = id => document.getElementById(id);
const title = mn ? 'Орчуулагч Ток-д урьж байна' : '통역톡 초대';
document.documentElement.lang = mn ? 'mn' : 'ko';
document.title = get('title').textContent = title;

if (/^[A-F0-9]{16}$/.test(code)) {
  get('notice').textContent = mn
    ? 'Урилгын кодыг хуулаад утсандаа тохирох дэлгүүрээс аппыг суулгана уу. Бүртгүүлэхдээ кодыг оруулаарай.'
    : '초대 코드를 복사하고 휴대폰에 맞는 스토어에서 통역톡을 설치해 주세요. 가입할 때 코드를 입력하면 초대가 연결됩니다.';
  get('invite').hidden = false;
  get('code').value = code;
  const play = new URL('https://play.google.com/store/apps/details');
  play.searchParams.set('id', 'com.tongyeoktalk');
  play.searchParams.set('referrer', 'tt_ref=' + code);
  get('android').href = play.href;
  get('ios').href = 'https://apps.apple.com/kr/app/id6834760087';
  if (mn) {
    get('code-label').textContent = 'Урилгын код';
    get('copy').textContent = 'Код хуулах';
    get('android').textContent = 'Android · Google Play';
    get('ios').textContent = 'iPhone · App Store';
  }
  const selected = { a: 'android', i: 'ios' }[param.get('p')];
  if (selected === 'android' || selected === 'ios') {
    const store = get(selected);
    get('stores').prepend(store);
    store.classList.add('primary');
  }
  get('copy').addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(code);
      get('result').textContent = mn ? 'Хууллаа' : '복사했어요';
    } catch {
      get('code').select();
      get('result').textContent = mn ? 'Кодыг хуулна уу' : '선택된 코드를 복사해 주세요';
    }
  });
} else if (mn) {
  get('notice').textContent = 'Урилгын холбоосоо шалгана уу.';
}
