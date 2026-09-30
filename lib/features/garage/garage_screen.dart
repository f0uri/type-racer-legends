import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/services/audio_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/misc.dart';
import '../../core/widgets/common.dart';
import '../../data/models/content_models.dart';
import '../../data/models/profile.dart';
import '../content/content_db.dart';
import '../content/new_items.dart';
import '../shop/economy.dart';
import 'effect_preview.dart';
import 'garage_widgets.dart';
import 'look.dart';
import 'turntable.dart';

class GarageScreen extends ConsumerStatefulWidget {
  const GarageScreen({super.key, this.embedded = false});
  final bool embedded;
  @override
  ConsumerState<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends ConsumerState<GarageScreen>
    with SingleTickerProviderStateMixin {
  late String _kind;
  late String _vehicleId;
  String _slot = 'paint';
  String? _pvKey, _pvId; // previewed (not yet equipped) skin
  String? _pvOutfit;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    final db = ref.read(contentProvider);
    final p = ref.read(profileProvider);
    final v = db.vehicle(p.selVehicle) ?? db.starterCar;
    _vehicleId = v.id;
    _kind = v.kind;
    _tabs = TabController(length: 3, vsync: this)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<Vehicle> _vehicles(ContentDb db, PlayerProfile p) {
    const order = {'common': 0, 'rare': 1, 'legendary': 2};
    final list = db.vehicles
        .where(
          (v) =>
              v.kind == _kind &&
              (Economy.ownsVehicle(p, v) || db.itemAvailable(v)),
        )
        .toList();
    list.sort((a, b) {
      final oa = Economy.ownsVehicle(p, a) ? 0 : 1,
          ob = Economy.ownsVehicle(p, b) ? 0 : 1;
      if (oa != ob) return oa.compareTo(ob);
      final r = (order[a.rarity] ?? 0).compareTo(order[b.rarity] ?? 0);
      return r != 0 ? r : a.price.coins.compareTo(b.price.coins);
    });
    return list;
  }

  Look _look(ContentDb db, PlayerProfile p, Vehicle v) {
    final lo = Map<String, dynamic>.from(p.loadout(v.id));
    if (_pvKey != null && _pvId != null) lo[_pvKey!] = _pvId;
    final plate = (p.settings['plateText'] as String?) ?? '';
    return Look.resolve(
      db,
      v,
      lo,
      outfitId: _pvOutfit ?? p.selOutfit,
      plateName: plate.isNotEmpty ? plate : p.name,
    );
  }

  void _clearPreview() {
    _pvKey = null;
    _pvId = null;
    _pvOutfit = null;
  }

  void _step(List<Vehicle> list, int d) {
    final i = list.indexWhere((v) => v.id == _vehicleId);
    final n = list[(i + d + list.length) % list.length];
    setState(() {
      _vehicleId = n.id;
      _clearPreview();
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(contentProvider);
    final p = ref.watch(profileProvider);
    final list = _vehicles(db, p);
    var v = db.vehicle(_vehicleId) ?? db.starterCar;
    if (v.kind != _kind && list.isNotEmpty) v = list.first;
    final owned = Economy.ownsVehicle(p, v);
    final look = _look(db, p, v);
    final equipped = p.selVehicle == v.id;
    if (NewItems.isNew(p, v.id)) {
      final vid = v.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(profileProvider.notifier).update((pp) => NewItems.markSeen(pp, [vid]), syncSoon: false);
      });
    }
    return Scaffold(
      body: GradientBg(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
                child: Row(
                  children: [
                    if (!widget.embedded)
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () => Navigator.of(context).maybePop(),
                      )
                    else
                      const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'الكراج',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                    ),
                    CurrencyChip(
                      icon: Icons.monetization_on,
                      color: C.gold,
                      value: fmtCompact(p.coins),
                    ),
                    const SizedBox(width: 6),
                    CurrencyChip(
                      icon: Icons.diamond,
                      color: C.cyan,
                      value: fmtCompact(p.gems),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 230,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Turntable(look: look, showRider: true),
                    ),
                    Positioned(
                      top: 4,
                      right: 12,
                      child: SegmentedButton<String>(
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 'car', label: Text('🚗 سيارات')),
                          ButtonSegment(
                            value: 'bike',
                            label: Text('🏍️ دراجات'),
                          ),
                        ],
                        selected: {_kind},
                        onSelectionChanged: (s) {
                          setState(() {
                            _kind = s.first;
                            final l = _vehicles(db, p);
                            final sel = db.vehicle(p.selVehicle);
                            _vehicleId = sel != null && sel.kind == _kind
                                ? sel.id
                                : (l.isEmpty ? _vehicleId : l.first.id);
                            _clearPreview();
                          });
                        },
                      ),
                    ),
                    Positioned(
                      left: 4,
                      top: 90,
                      child: IconButton.filledTonal(
                        icon: const Icon(Icons.chevron_left_rounded),
                        onPressed: list.length < 2
                            ? null
                            : () => _step(list, -1),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      top: 90,
                      child: IconButton.filledTonal(
                        icon: const Icon(Icons.chevron_right_rounded),
                        onPressed: list.length < 2
                            ? null
                            : () => _step(list, 1),
                      ),
                    ),
                    Positioned(
                      bottom: 6,
                      left: 12,
                      right: 12,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              loc(v.name),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                shadows: [
                                  Shadow(blurRadius: 8, color: Colors.black),
                                ],
                              ),
                            ),
                          ),
                          if (NewItems.isNew(p, v.id)) ...[const NewBadge(), const SizedBox(width: 6)],
                    RarityBadge(v.rarity),
                          const SizedBox(width: 8),
                          const Text(
                            '↔ اسحب للتدوير',
                            style: TextStyle(color: C.textDim, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(text: 'الأداء'),
                  Tab(text: 'التخصيص'),
                  Tab(text: 'الزي'),
                ],
                labelColor: C.cyan,
                indicatorColor: C.cyan,
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _perfTab(db, p, v, owned, equipped),
                    owned ? _customTab(db, p, v, look) : _lockedNote(db, p, v),
                    _outfitTab(db, p),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ performance
  Widget _perfTab(
    ContentDb db,
    PlayerProfile p,
    Vehicle v,
    bool owned,
    bool equipped,
  ) {
    final up = db.econ('upgrade');
    final per = (up['bonusPerLevel'] as num?)?.toDouble() ?? 0.03;
    final maxLvl = (up['maxLevel'] as num?)?.toInt() ?? 5;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
      children: [
        if (!owned) _buyCard(db, p, v),
        if (owned && !equipped)
          NeonButton(
            label: 'استخدم هذه المركبة في السباقات',
            icon: Icons.check_circle_rounded,
            onPressed: () {
              ref
                  .read(profileProvider.notifier)
                  .update((pp) => pp.select(vehicle: v.id));
              toast(context, 'تم اختيار ${loc(v.name)}');
            },
          ),
        if (owned && equipped)
          const Panel(
            child: Text(
              '✅ هذه مركبتك الحالية في السباقات',
              style: TextStyle(color: C.green, fontWeight: FontWeight.w800),
            ),
          ),
        const SizedBox(height: 8),
        for (final s in Economy.stats)
          _statRow(db, p, v, s, owned, maxLvl, per),
      ],
    );
  }

  Widget _statRow(
    ContentDb db,
    PlayerProfile p,
    Vehicle v,
    String stat,
    bool owned,
    int maxLvl,
    double per,
  ) {
    final base = v.stat(stat);
    final lvl = owned ? p.upgradeLevel(v.id, stat) : 0;
    final q = Economy.upgradeQuote(db, p, v, stat);
    final can = owned && !q.maxed && p.coins >= q.cost;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Panel(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    Economy.statNames[stat]!,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  '$base/10',
                  style: const TextStyle(color: C.textDim, fontSize: 12),
                ),
                const SizedBox(width: 10),
                for (var i = 0; i < maxLvl; i++)
                  Icon(
                    i < lvl ? Icons.circle : Icons.circle_outlined,
                    size: 11,
                    color: i < lvl ? C.gold : Colors.white24,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            ProgressBar(value: base / 10, color: C.cyan, height: 7),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    VehicleMods2.effect(stat, db, base, lvl, per),
                    style: const TextStyle(color: C.textDim, fontSize: 12),
                  ),
                ),
                if (owned)
                  SizedBox(
                    height: 34,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: q.maxed
                            ? Colors.white12
                            : (can ? C.gold : Colors.white24),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: q.maxed ? null : () => _upgrade(db, v, stat),
                      child: Text(
                        q.maxed ? 'الحد الأقصى' : 'ترقية 🪙 ${fmtInt(q.cost)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: q.maxed ? Colors.white54 : Colors.black,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _upgrade(ContentDb db, Vehicle v, String stat) {
    BuyResult r = BuyResult.ok;
    ref
        .read(profileProvider.notifier)
        .update((p) => r = Economy.upgrade(db, p, v, stat));
    if (r == BuyResult.ok) {
      ref.read(audioProvider).play(Sfx.coin);
      toast(context, 'تمت الترقية ✅');
    } else if (r == BuyResult.notEnoughCoins) {
      toast(context, 'لا تملك عملات كافية');
    }
  }

  Widget _buyCard(ContentDb db, PlayerProfile p, Vehicle v) {
    final a = Economy.availability(db, p, v);
    return Panel(
      border: C.rarity(v.rarity),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🔒 مركبة غير مملوكة',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          if (a.canBuy)
            NeonButton(
              label: 'شراء  ${priceText(v.price)}',
              icon: Icons.shopping_cart_rounded,
              color: C.gold,
              onPressed: () => _buy(db, v),
            )
          else
            Text(
              a.label,
              style: const TextStyle(
                color: C.gold,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _buy(
    ContentDb db,
    CatalogItem item, {
    String? equipKey,
    Vehicle? equipOn,
  }) async {
    if (item.price.gems > 0 &&
        !await confirmDialog(
          context,
          'تأكيد الشراء',
          'سيتم خصم ${item.price.gems} جوهرة.',
          ok: 'شراء',
          okColor: C.gold,
        ))
      return;
    BuyResult r = BuyResult.ok;
    ref.read(profileProvider.notifier).update((p) {
      r = Economy.buy(db, p, item);
      if (r == BuyResult.ok && equipKey != null && equipOn != null)
        Economy.equip(p, equipOn, equipKey, item.id);
    });
    if (!mounted) return;
    switch (r) {
      case BuyResult.ok:
        ref.read(audioProvider).play(Sfx.chest);
        toast(context, 'تم الشراء 🎉');
        setState(() {
          if (equipKey != null) _clearPreview();
        });
        break;
      case BuyResult.notEnoughCoins:
        toast(context, 'لا تملك عملات كافية');
        break;
      case BuyResult.notEnoughGems:
        toast(context, 'لا تملك جواهر كافية');
        break;
      default:
        toast(context, 'غير متاح للشراء');
    }
  }

  // ------------------------------------------------------------------ customise
  Widget _lockedNote(ContentDb db, PlayerProfile p, Vehicle v) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'امتلك المركبة أولاً لتخصيصها. يمكنك مع ذلك معاينة الألوان بتدوير المجسم.',
        textAlign: TextAlign.center,
        style: TextStyle(color: C.textDim),
      ),
    ),
  );

  Widget _customTab(ContentDb db, PlayerProfile p, Vehicle v, Look look) {
    final slotKeys = Economy.slots
        .where((k) => k != 'sticker2' || true)
        .toList();
    final skinSlot = Economy.slotOf(_slot);
    final skins = Economy.skinsFor(db, p, v, skinSlot);
    final lo = p.loadout(v.id);
    final pv = _pvId == null ? null : db.skin(_pvId!);
    final effMode = switch (skinSlot) {
      'exhaust' => EffectMode.exhaust,
      'nitroFlame' => EffectMode.flame,
      'celebration' => EffectMode.celebration,
      _ => null,
    };
    return Column(
      children: [
        SizedBox(
          height: 46,
          child: ListView.builder(
          key: const Key('slotChips'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            itemCount: slotKeys.length,
            itemBuilder: (_, i) {
              final k = slotKeys[i];
              final sel = k == _slot;
              return Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(
                  selected: sel,
                  label: Text('${slotLabels[k]!.$1} ${slotLabels[k]!.$2}'),
                  onSelected: (_) => setState(() {
                    _slot = k;
                    _clearPreview();
                  }),
                ),
              );
            },
          ),
        ),
        if (effMode != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: EffectPreview(look: look, mode: effMode, height: 84),
          ),
        Expanded(
          child: skins.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد عناصر لهذه الفتحة',
                    style: TextStyle(color: C.textDim),
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                  itemCount: skins.length + (_slot == 'paint' ? 0 : 1),
                  itemBuilder: (_, i) {
                    if (_slot != 'paint' && i == 0) {
                      return ItemTile(
                        preview: const Icon(
                          Icons.block_rounded,
                          color: Colors.white38,
                          size: 30,
                        ),
                        name: 'بدون',
                        rarity: 'common',
                        equipped: lo[_slot] == null,
                        selected: _pvKey == _slot && _pvId == null,
                        priceLabel: '—',
                        onTap: () {
                          ref
                              .read(profileProvider.notifier)
                              .update(
                                (pp) => Economy.equip(pp, v, _slot, null),
                              );
                          setState(_clearPreview);
                        },
                      );
                    }
                    final s = skins[_slot == 'paint' ? i : i - 1];
                    final own = Economy.ownsSkin(p, s);
                    final av = Economy.availability(db, p, s);
                    final preview =
                        (skinSlot == 'paint' ||
                            skinSlot == 'rims' ||
                            skinSlot == 'neon')
                        ? MiniVehicle(
                            look: Look.resolve(db, v, {
                              ...lo,
                              _slot: s.id,
                            }, plateName: look.plateText),
                          )
                        : SkinGlyph(skin: s, look: look);
                    return ItemTile(
                      preview: preview,
                      name: loc(s.name),
                      rarity: s.rarity,
                      equipped: lo[_slot] == s.id,
                    isNew: NewItems.isNew(p, s.id),
                      selected: _pvId == s.id && _pvKey == _slot,
                      locked: !own && !av.canBuy,
                      priceLabel: own ? 'مملوك' : priceText(s.price),
                      onTap: () {
                        setState(() {
                          _pvKey = _slot;
                          _pvId = s.id;
                        });
                        if (s.slot == 'horn') _playHorn(s);
                      },
                    );
                  },
                ),
        ),
        _actionBar(db, p, v, pv, lo),
      ],
    );
  }

  void _playHorn(Skin s) {
    final a = ref.read(audioProvider);
    a.setHorn(
      ((s.params['seq'] as List?) ?? const [])
          .map((e) => (e as List).map((x) => x as num).toList())
          .toList(),
      (s.params['wave'] as String?) ?? 'saw',
    );
    a.play(Sfx.horn);
  }

  Widget _actionBar(
    ContentDb db,
    PlayerProfile p,
    Vehicle v,
    Skin? pv,
    Map<String, dynamic> lo,
  ) {
    Widget child;
    if (pv == null) {
      child = _slot == 'plate'
          ? NeonButton(
              label: 'تعديل نص اللوحة',
              icon: Icons.edit_rounded,
              filled: false,
              height: 44,
              onPressed: () => _editPlate(p),
            )
          : const Text(
              'اختر عنصراً للمعاينة على المركبة',
              style: TextStyle(color: C.textDim, fontSize: 12),
            );
    } else {
      final own = Economy.ownsSkin(p, pv);
      final av = Economy.availability(db, p, pv);
      if (lo[_pvKey] == pv.id) {
        child = const Text(
          '✓ مجهّز حالياً',
          style: TextStyle(color: C.green, fontWeight: FontWeight.w900),
        );
      } else if (own) {
        child = NeonButton(
          label: 'تجهيز ${loc(pv.name)}',
          icon: Icons.check_rounded,
          height: 44,
          onPressed: () {
            ref
                .read(profileProvider.notifier)
                .update((pp) => Economy.equip(pp, v, _pvKey!, pv.id));
            setState(_clearPreview);
            toast(context, 'تم التجهيز');
          },
        );
      } else if (av.canBuy) {
        child = NeonButton(
          label: 'شراء وتجهيز  ${priceText(pv.price)}',
          icon: Icons.shopping_cart_rounded,
          color: C.gold,
          height: 44,
          onPressed: () => _buy(db, pv, equipKey: _pvKey, equipOn: v),
        );
      } else {
        child = Text(
          av.label,
          style: const TextStyle(color: C.gold, fontWeight: FontWeight.w800),
        );
      }
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      alignment: Alignment.center,
      height: 62,
      child: child,
    );
  }

  Future<void> _editPlate(PlayerProfile p) async {
    final c = TextEditingController(
      text: (p.settings['plateText'] as String?) ?? '',
    );
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('نص اللوحة'),
        content: TextField(
          controller: c,
          maxLength: 7,
          textCapitalization: TextCapitalization.characters,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            hintText: 'مثال: SPEED1',
            helperText: 'أحرف إنجليزية وأرقام فقط',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    c.dispose();
    if (v == null) return;
    final clean = v.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    ref
        .read(profileProvider.notifier)
        .update((pp) => pp.setSetting('plateText', clean));
  }

  // ------------------------------------------------------------------ outfits
  Widget _outfitTab(ContentDb db, PlayerProfile p) {
    final list = db.outfits
        .where((o) => Economy.ownsOutfit(p, o) || db.itemAvailable(o))
        .toList();
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 118,
            ),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final o = list[i];
              final own = Economy.ownsOutfit(p, o);
              final av = Economy.availability(db, p, o);
              final look = OutfitLook(
                hexColor(o.params['helmet'] as String?),
                hexColor(o.params['suit'] as String?),
                hexColor(o.params['suit2'] as String?),
                hexColor(o.params['visor'] as String?),
                (o.params['style'] as String?) ?? 'full',
              );
              return ItemTile(
                preview: CustomPaint(
                  size: const Size(44, 50),
                  painter: _RiderIcon(look),
                ),
                name: loc(o.name),
                rarity: o.rarity,
                equipped: p.selOutfit == o.id,
                selected: _pvOutfit == o.id,
                locked: !own && !av.canBuy,
                priceLabel: own ? 'مملوك' : priceText(o.price),
                onTap: () => setState(() => _pvOutfit = o.id),
              );
            },
          ),
        ),
        Builder(
          builder: (_) {
            final o = _pvOutfit == null ? null : db.outfit(_pvOutfit!);
            Widget child = const Text(
              'اختر زياً لمعاينته على السائق',
              style: TextStyle(color: C.textDim, fontSize: 12),
            );
            if (o != null) {
              final own = Economy.ownsOutfit(p, o);
              final av = Economy.availability(db, p, o);
              if (p.selOutfit == o.id) {
                child = const Text(
                  '✓ مجهّز حالياً',
                  style: TextStyle(color: C.green, fontWeight: FontWeight.w900),
                );
              } else if (own) {
                child = NeonButton(
                  label: 'تجهيز الزي',
                  height: 44,
                  onPressed: () {
                    ref
                        .read(profileProvider.notifier)
                        .update((pp) => pp.select(outfit: o.id));
                    setState(() => _pvOutfit = null);
                  },
                );
              } else if (av.canBuy) {
                child = NeonButton(
                  label: 'شراء الزي  ${priceText(o.price)}',
                  color: C.gold,
                  height: 44,
                  onPressed: () async {
                    await _buy(db, o);
                    ref.read(profileProvider.notifier).update((pp) {
                      if (pp.ownsOutfit(o.id)) pp.select(outfit: o.id);
                    });
                    if (mounted) setState(() => _pvOutfit = null);
                  },
                );
              } else {
                child = Text(
                  av.label,
                  style: const TextStyle(
                    color: C.gold,
                    fontWeight: FontWeight.w800,
                  ),
                );
              }
            }
            return Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              height: 62,
              alignment: Alignment.center,
              child: child,
            );
          },
        ),
      ],
    );
  }
}

class _RiderIcon extends CustomPainter {
  final OutfitLook o;
  _RiderIcon(this.o);
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint();
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          s.width * 0.18,
          s.height * 0.42,
          s.width * 0.64,
          s.height * 0.56,
        ),
        const Radius.circular(10),
      ),
      p..color = o.suit,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        s.width * 0.44,
        s.height * 0.42,
        s.width * 0.12,
        s.height * 0.56,
      ),
      p..color = o.suit2,
    );
    canvas.drawCircle(
      Offset(s.width / 2, s.height * 0.26),
      s.width * 0.26,
      p..color = o.helmet,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(s.width / 2, s.height * 0.27),
          width: s.width * 0.36,
          height: s.height * 0.12,
        ),
        const Radius.circular(4),
      ),
      p..color = o.visor,
    );
  }

  @override
  bool shouldRepaint(covariant _RiderIcon old) => old.o != o;
}
