import 'package:flutter/material.dart';

const countries = <String, String>{
  'MA': 'المغرب', 'DZ': 'الجزائر', 'TN': 'تونس', 'EG': 'مصر', 'LY': 'ليبيا', 'SD': 'السودان', 'SA': 'السعودية', 'AE': 'الإمارات', 'QA': 'قطر',
  'KW': 'الكويت', 'BH': 'البحرين', 'OM': 'عُمان', 'JO': 'الأردن', 'LB': 'لبنان', 'SY': 'سوريا', 'IQ': 'العراق', 'PS': 'فلسطين', 'YE': 'اليمن',
  'MR': 'موريتانيا', 'SN': 'السنغال', 'NG': 'نيجيريا', 'ZA': 'جنوب أفريقيا', 'TR': 'تركيا', 'IR': 'إيران', 'PK': 'باكستان', 'IN': 'الهند',
  'ID': 'إندونيسيا', 'MY': 'ماليزيا', 'FR': 'فرنسا', 'ES': 'إسبانيا', 'IT': 'إيطاليا', 'DE': 'ألمانيا', 'GB': 'بريطانيا', 'NL': 'هولندا',
  'BE': 'بلجيكا', 'CH': 'سويسرا', 'PT': 'البرتغال', 'SE': 'السويد', 'US': 'الولايات المتحدة', 'CA': 'كندا', 'BR': 'البرازيل', 'AR': 'الأرجنتين',
  'MX': 'المكسيك', 'JP': 'اليابان', 'KR': 'كوريا الجنوبية', 'CN': 'الصين', 'RU': 'روسيا', 'AU': 'أستراليا',
};

/// Player avatar glyphs. Vector icons, never emoji: an emoji avatar renders differently on every
/// Android build (and not at all in some fonts), while these always look the same and scale cleanly.
const avatars = <IconData>[
  Icons.sports_motorsports,
  Icons.two_wheeler,
  Icons.pets,
  Icons.bolt,
  Icons.local_fire_department,
  Icons.workspace_premium,
  Icons.rocket_launch,
  Icons.star,
  Icons.shield,
  Icons.sports_score,
  Icons.military_tech,
  Icons.auto_awesome,
];
