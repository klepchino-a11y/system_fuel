local Translations = {
    progress = {
        refueling = 'جاري التزويد بالوقود...',
    },
    success = {
        refueled = 'تم تزويد المركبة بالوقود',
    },
    error = {
        no_money    = 'ليس لديك ما يكفي من المال',
        no_vehicle  = 'لم يتم العثور على مركبة قريبة',
        no_vehicles = 'لا توجد مركبات قريبة',
        no_jerrycan = 'ليس لديك جالون وقود',
        vehicle_full = 'المركبة ممتلئة بالوقود بالفعل',
        no_fuel_can = 'لا يوجد وقود في جالون الوقود',
        no_nozzle   = 'لا توجد مركبة قريبة موصول بها الفوهة',
        too_far     = 'أنت بعيد جدًا عن المضخة، تم إرجاع الفوهة',
        wrong_side  = 'خزان المركبة في الجهة الأخرى',
    },
    target = {
        put_fuel         = 'تعبئة الوقود',
        get_nozzle       = 'أخذ الفوهة',
        buy_jerrycan     = 'شراء جالون وقود $%{price}',
        refill_jerrycan  = 'إعادة تعبئة الجالون $%{price}',
        refill_fuel      = 'إعادة تعبئة الوقود',
        nozzle_put       = 'توصيل الفوهة',
        nozzle_remove    = 'إزالة الفوهة',
        return_nozzle    = 'إرجاع الفوهة',
    }
}

Lang = Lang or Locale:new({
    phrases = Translations,
    warnOnMissing = true
})
