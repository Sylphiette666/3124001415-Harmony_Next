export const CARD_GROUPS: string[] = ['同学', '老师', '工作', '其他'];

export class BusinessCard {
  id: string = '';
  name: string = '';
  organization: string = '';
  title: string = '';
  phone: string = '';
  email: string = '';
  address: string = '';
  note: string = '';
  group: string = '其他';
  favorite: boolean = false;
  createdAt: number = 0;
  updatedAt: number = 0;
}

// 返回独立对象，编辑或筛选结果不会意外修改原始列表。
export function copyCard(card: BusinessCard): BusinessCard {
  const copy = new BusinessCard();
  copy.id = card.id;
  copy.name = card.name;
  copy.organization = card.organization;
  copy.title = card.title;
  copy.phone = card.phone;
  copy.email = card.email;
  copy.address = card.address;
  copy.note = card.note;
  copy.group = card.group;
  copy.favorite = card.favorite;
  copy.createdAt = card.createdAt;
  copy.updatedAt = card.updatedAt;
  return copy;
}

export function validateCard(card: BusinessCard): string {
  if (card === null || typeof card !== 'object' || Array.isArray(card) ||
    typeof card.id !== 'string' || typeof card.name !== 'string' ||
    typeof card.organization !== 'string' || typeof card.title !== 'string' ||
    typeof card.phone !== 'string' || typeof card.email !== 'string' ||
    typeof card.address !== 'string' || typeof card.note !== 'string' ||
    typeof card.group !== 'string' || typeof card.favorite !== 'boolean' ||
    typeof card.createdAt !== 'number' || typeof card.updatedAt !== 'number') {
    return '名片数据格式不正确';
  }
  if (card.name.trim().length === 0) {
    return '请填写姓名';
  }
  if (card.name.trim().length > 40) {
    return '姓名最多 40 个字符';
  }
  if (card.organization.trim().length > 60 || card.title.trim().length > 40) {
    return '单位最多 60 个字符，职位最多 40 个字符';
  }
  if (card.address.trim().length > 160 || card.note.trim().length > 500) {
    return '地址最多 160 个字符，备注最多 500 个字符';
  }
  const phone = card.phone.trim();
  const email = card.email.trim();
  if (phone.length === 0 && email.length === 0) {
    return '请至少填写电话或邮箱中的一项';
  }
  if (phone.length > 0 && (phone.length > 30 || !/^\+?[0-9 ()-]+$/.test(phone) ||
    phone.replace(/[^0-9]/g, '').length < 6 || phone.replace(/[^0-9]/g, '').length > 20)) {
    return '请输入有效电话（6–20 位数字，可含 +、空格、括号和短横线）';
  }
  if (email.length > 0 && (email.length > 120 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))) {
    return '请输入有效邮箱，例如 name@example.com';
  }
  if (CARD_GROUPS.indexOf(card.group) < 0) {
    return '请选择有效的名片分组';
  }
  const singleLineFields: string[] = [card.name, card.organization, card.title, card.phone,
    card.email, card.address, card.group];
  if (singleLineFields.some((value: string) => /[\u0000-\u001F\u007F]/.test(value)) ||
    /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/.test(card.note)) {
    return '名片中包含不支持的控制字符';
  }
  return '';
}

export function filterCards(cards: BusinessCard[], query: string, group: string = '全部',
  favoritesOnly: boolean = false): BusinessCard[] {
  const keyword = query.trim().toLocaleLowerCase();
  return cards.filter((card: BusinessCard) => {
    if ((group !== '全部' && card.group !== group) || (favoritesOnly && !card.favorite)) {
      return false;
    }
    const searchable = [card.name, card.organization, card.title, card.phone, card.email]
      .join('\n').toLocaleLowerCase();
    return keyword.length === 0 || searchable.indexOf(keyword) >= 0;
  }).map((card: BusinessCard) => copyCard(card)).sort((left: BusinessCard, right: BusinessCard) => {
    if (left.favorite !== right.favorite) {
      return left.favorite ? -1 : 1;
    }
    if (left.updatedAt !== right.updatedAt) {
      return right.updatedAt - left.updatedAt;
    }
    return left.id.localeCompare(right.id);
  });
}
