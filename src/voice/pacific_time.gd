class_name PacificTime
extends RefCounted
## Полночь America/Los_Angeles от метки UTC. Часовой пояс устройства не используется.
## Летнее время США: второе воскресенье марта 02:00 PST и первое воскресенье ноября 02:00 PDT.


const PST := -8 * 3600
const PDT := -7 * 3600


static func next_midnight_utc(utc_unix: int) -> int:
	var local := utc_unix + offset_seconds(utc_unix)
	var next_day := int(floor(float(local) / 86400.0)) + 1
	var date := _date_from_days(next_day)
	return _midnight_utc(int(date.year), int(date.month), int(date.day))


static func format_local(utc_unix: int) -> String:
	var local := utc_unix + offset_seconds(utc_unix)
	var days := int(floor(float(local) / 86400.0))
	var date := _date_from_days(days)
	var seconds := posmod(local, 86400)
	var hour := int(seconds / 3600)
	var minute := int(seconds / 60) % 60
	return "%04d-%02d-%02d %02d:%02d PT" % [int(date.year), int(date.month), int(date.day), hour, minute]


static func offset_seconds(utc_unix: int) -> int:
	var year := _year(utc_unix)
	if utc_unix >= _dst_start_utc(year) and utc_unix < _dst_end_utc(year):
		return PDT
	return PST


static func _midnight_utc(year: int, month: int, day: int) -> int:
	var as_pst := _utc(year, month, day, 8, 0, 0)
	if offset_seconds(as_pst) == PDT:
		return _utc(year, month, day, 7, 0, 0)
	return as_pst


static func _dst_start_utc(year: int) -> int:
	return _utc(year, 3, _nth_sunday(year, 3, 2), 10, 0, 0)


static func _dst_end_utc(year: int) -> int:
	return _utc(year, 11, _nth_sunday(year, 11, 1), 9, 0, 0)


static func _nth_sunday(year: int, month: int, index: int) -> int:
	var first := _weekday(_utc(year, month, 1, 0, 0, 0))
	return 1 + ((7 - first) % 7) + (index - 1) * 7


static func _weekday(utc_unix: int) -> int:
	return (int(floor(float(utc_unix) / 86400.0)) + 4) % 7


static func _year(utc_unix: int) -> int:
	return int(_date_from_days(int(floor(float(utc_unix) / 86400.0))).year)


static func _date_from_days(days: int) -> Dictionary:
	var year := 1970
	while true:
		var length := 366 if _leap(year) else 365
		if days < length:
			break
		days -= length
		year += 1
	var lengths: Array[int] = [31, 29 if _leap(year) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var month := 1
	for length in lengths:
		if days < length:
			break
		days -= length
		month += 1
	return {"year": year, "month": month, "day": days + 1}


static func _utc(year: int, month: int, day: int, hour: int, minute: int, second: int) -> int:
	var days := 0
	for past in range(1970, year):
		days += 366 if _leap(past) else 365
	var lengths: Array[int] = [31, 29 if _leap(year) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	for index in range(month - 1):
		days += lengths[index]
	days += day - 1
	return days * 86400 + hour * 3600 + minute * 60 + second


static func _leap(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
