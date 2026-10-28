import 'package:flutter/material.dart';

IconData legacyCategoryIcon(String name) => switch (name) {
  '居住' => Icons.home_outlined,
  '水电话费' => Icons.bolt_outlined,
  '交通' => Icons.directions_bus_outlined,
  '普通餐饮' || '饮食' || '餐饮' || '食物' => Icons.restaurant_outlined,
  '娱乐餐饮' => Icons.local_bar_outlined,
  '购物' => Icons.shopping_bag_outlined,
  '文化教育' || '教育' => Icons.school_outlined,
  '周边' => Icons.auto_awesome_outlined,
  '娱乐' => Icons.movie_outlined,
  '游戏' => Icons.sports_esports_outlined,
  '健身' => Icons.fitness_center,
  '音乐' => Icons.music_note_outlined,
  '保险' => Icons.shield_outlined,
  '医疗' => Icons.medical_services_outlined,
  '赡养' => Icons.elderly,
  '人情' => Icons.card_giftcard,
  '理财亏损' || '投资' => Icons.trending_up,
  'AI-Token' || 'AI Token' => Icons.smart_toy_outlined,
  '工资' => Icons.work_outline,
  '补贴' => Icons.support_outlined,
  '副业' => Icons.handyman_outlined,
  '奖金' || '中奖' => Icons.emoji_events_outlined,
  '闲置' => Icons.recycling,
  '报销' => Icons.receipt_long_outlined,
  '买菜' || '水果零食' => Icons.local_grocery_store_outlined,
  '咖啡茶饮' => Icons.local_cafe_outlined,
  '日用品' => Icons.cleaning_services_outlined,
  '服饰鞋包' || '衣物' => Icons.checkroom_outlined,
  '数码电器' || '数码产品' => Icons.devices_outlined,
  '家具' => Icons.chair_outlined,
  '旅行' => Icons.flight_outlined,
  '宠物' => Icons.pets_outlined,
  '美容护理' || '化妆品' => Icons.spa_outlined,
  '会员订阅' => Icons.subscriptions_outlined,
  '通讯网络' => Icons.wifi_outlined,
  '汽车养护' => Icons.directions_car_outlined,
  '育儿' => Icons.child_care_outlined,
  '手续费' || '余额调整' => Icons.tune,
  '利息' || '分红' => Icons.trending_up,
  '租金' => Icons.home_work_outlined,
  '稿费' => Icons.edit_note_outlined,
  '退款' => Icons.undo,
  _ => Icons.category_outlined,
};

class CategoryIconOption {
  const CategoryIconOption(this.id, this.name, this.group, this.icon);
  final String id, name, group;
  final IconData icon;
}

const categoryIconCatalog = <CategoryIconOption>[
  CategoryIconOption('restaurant', '餐饮', '餐饮', Icons.restaurant_outlined),
  CategoryIconOption(
    'groceries',
    '买菜',
    '餐饮',
    Icons.local_grocery_store_outlined,
  ),
  CategoryIconOption('cafe', '咖啡茶饮', '餐饮', Icons.local_cafe_outlined),
  CategoryIconOption('bar', '酒吧聚餐', '餐饮', Icons.local_bar_outlined),
  CategoryIconOption('breakfast', '早餐', '餐饮', Icons.bakery_dining_outlined),
  CategoryIconOption('noodles', '面食', '餐饮', Icons.ramen_dining_outlined),
  CategoryIconOption('adjust', '手续费余额调整', '工作收入', Icons.tune),
  CategoryIconOption('cake', '蛋糕零食', '餐饮', Icons.cake_outlined),
  CategoryIconOption('home', '居住', '居家', Icons.home_outlined),
  CategoryIconOption('utilities', '水电燃气', '居家', Icons.bolt_outlined),
  CategoryIconOption('cleaning', '日用品', '居家', Icons.cleaning_services_outlined),
  CategoryIconOption('furniture', '家具', '居家', Icons.chair_outlined),
  CategoryIconOption('kitchen', '厨具', '居家', Icons.kitchen_outlined),
  CategoryIconOption('bed', '床品', '居家', Icons.bed_outlined),
  CategoryIconOption('tools', '工具维修', '居家', Icons.build_outlined),
  CategoryIconOption('pets', '宠物', '居家', Icons.pets_outlined),
  CategoryIconOption('bus', '交通公交', '出行', Icons.directions_bus_outlined),
  CategoryIconOption('car', '汽车养护', '出行', Icons.directions_car_outlined),
  CategoryIconOption('flight', '旅行机票', '出行', Icons.flight_outlined),
  CategoryIconOption('train', '火车', '出行', Icons.train_outlined),
  CategoryIconOption('bike', '自行车', '出行', Icons.pedal_bike_outlined),
  CategoryIconOption('taxi', '打车', '出行', Icons.local_taxi_outlined),
  CategoryIconOption('fuel', '加油', '出行', Icons.local_gas_station_outlined),
  CategoryIconOption('hotel', '酒店住宿', '出行', Icons.hotel_outlined),
  CategoryIconOption('shopping', '购物', '购物', Icons.shopping_bag_outlined),
  CategoryIconOption('clothes', '服饰鞋包', '购物', Icons.checkroom_outlined),
  CategoryIconOption('gift', '礼物人情', '购物', Icons.card_giftcard),
  CategoryIconOption('beauty', '美容护理', '购物', Icons.spa_outlined),
  CategoryIconOption('baby', '育儿', '购物', Icons.child_care_outlined),
  CategoryIconOption('delivery', '快递', '购物', Icons.local_shipping_outlined),
  CategoryIconOption('jewelry', '饰品', '购物', Icons.diamond_outlined),
  CategoryIconOption('category', '通用分类', '购物', Icons.category_outlined),
  CategoryIconOption('devices', '数码电器', '数码', Icons.devices_outlined),
  CategoryIconOption('phone', '手机', '数码', Icons.smartphone_outlined),
  CategoryIconOption('computer', '电脑', '数码', Icons.computer_outlined),
  CategoryIconOption('headphones', '耳机', '数码', Icons.headphones_outlined),
  CategoryIconOption('camera', '相机', '数码', Icons.camera_alt_outlined),
  CategoryIconOption('wifi', '通讯网络', '数码', Icons.wifi_outlined),
  CategoryIconOption('ai', '人工智能', '数码', Icons.smart_toy_outlined),
  CategoryIconOption(
    'subscription',
    '会员订阅',
    '数码',
    Icons.subscriptions_outlined,
  ),
  CategoryIconOption('movie', '娱乐电影', '文娱', Icons.movie_outlined),
  CategoryIconOption('game', '游戏', '文娱', Icons.sports_esports_outlined),
  CategoryIconOption('music', '音乐', '文娱', Icons.music_note_outlined),
  CategoryIconOption('school', '文化教育', '文娱', Icons.school_outlined),
  CategoryIconOption('book', '图书', '文娱', Icons.menu_book_outlined),
  CategoryIconOption('art', '绘画', '文娱', Icons.palette_outlined),
  CategoryIconOption('sparkles', '周边收藏', '文娱', Icons.auto_awesome_outlined),
  CategoryIconOption('sports', '运动球类', '文娱', Icons.sports_basketball_outlined),
  CategoryIconOption('fitness', '健身', '健康', Icons.fitness_center),
  CategoryIconOption('medical', '医疗', '健康', Icons.medical_services_outlined),
  CategoryIconOption('shield', '保险', '健康', Icons.shield_outlined),
  CategoryIconOption('elderly', '赡养', '健康', Icons.elderly),
  CategoryIconOption('medicine', '药品', '健康', Icons.medication_outlined),
  CategoryIconOption('rent', '租金', '工作收入', Icons.home_work_outlined),
  CategoryIconOption('refund', '退款', '工作收入', Icons.undo),
  CategoryIconOption('heart', '健康护理', '健康', Icons.favorite_outline),
  CategoryIconOption('work', '工资工作', '工作收入', Icons.work_outline),
  CategoryIconOption('support', '补贴', '工作收入', Icons.support_outlined),
  CategoryIconOption('sidejob', '副业', '工作收入', Icons.handyman_outlined),
  CategoryIconOption('trophy', '奖金中奖', '工作收入', Icons.emoji_events_outlined),
  CategoryIconOption('recycle', '闲置', '工作收入', Icons.recycling),
  CategoryIconOption('receipt', '报销', '工作收入', Icons.receipt_long_outlined),
  CategoryIconOption('investment', '投资理财利息分红', '工作收入', Icons.trending_up),
  CategoryIconOption('edit', '稿费', '工作收入', Icons.edit_note_outlined),
];

String defaultCategoryIconId(String name) =>
    categoryIconCatalog
        .where((o) => o.icon == legacyCategoryIcon(name))
        .firstOrNull
        ?.id ??
    'category';

/// Explicit unknown IDs use the generic icon; only absent IDs use legacy names.
IconData categoryIcon(String name, {String? iconId}) => iconId == null
    ? legacyCategoryIcon(name)
    : categoryIconCatalog.where((o) => o.id == iconId).firstOrNull?.icon ??
          Icons.category_outlined;
