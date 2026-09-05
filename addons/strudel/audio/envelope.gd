@tool
class_name StrudelEnvelope
extends RefCounted

## Огибающая ADSR. Перенос `getADSRValues` и `getParamADSR`
## из `packages/superdough/helpers.mjs`.
##
## 🔴 Значения по умолчанию НЕ нулевые и не «музыкальные на глаз»:
## [0.001, 0.001, 1, 0.01]. И они меняются от того, ЧТО задал пользователь:
## `.decay(0.2)` без attack ведёт себя как чистый спад, а `.attack(0.3)` без
## decay — как нарастание с полным сустейном. Это правило из helpers.mjs:191,
## без него `.attack(0.3).release(1.2)` в треке звучит обрубленно.

const ENV_MIN := 0.001
const RELEASE_MIN := 0.01
const ENV_MAX := 1.0

var attack := ENV_MIN
var decay := ENV_MIN
var sustain := ENV_MAX
var release := RELEASE_MIN


## Умолчания СИНТЕЗА — свои (`synth.mjs:48`): нота сама подсаживается до 0.6
## за пятьдесят миллисекунд. У сэмплера умолчания общие.
const SYNTH_DEFAULTS := [0.001, 0.05, 0.6, 0.01]


static func from_values(a: Variant, d: Variant, s: Variant, r: Variant,
		defaults: Array = []) -> StrudelEnvelope:
	var env := StrudelEnvelope.new()
	if a == null and d == null and s == null and r == null:
		if defaults.size() == 4:
			env.attack = float(defaults[0])
			env.decay = float(defaults[1])
			env.sustain = float(defaults[2])
			env.release = float(defaults[3])
		return env
	var sus: float
	if s != null:
		sus = float(s)
	elif (a != null and d == null) or (a == null and d == null):
		sus = ENV_MAX
	else:
		sus = ENV_MIN
	env.attack = maxf(float(a) if a != null else 0.0, ENV_MIN)
	env.decay = maxf(float(d) if d != null else 0.0, ENV_MIN)
	env.sustain = minf(sus, ENV_MAX)
	env.release = maxf(float(r) if r != null else 0.0, RELEASE_MIN)
	return env

# 🔴 ЗДЕСЬ ЖИЛ `level_at` — ВТОРАЯ КОПИЯ ФОРМЫ ОГИБАЮЩЕЙ.
#
# Настоящая форма считается в теле цикла `StrudelVoice.render`, где она
# развёрнута ради цены: вызов функции в GDScript стоит больше самой
# арифметики. `level_at` был её независимым двойником, который никто не
# звал, кроме него самого, и ничто не проверяло. Любая правка формы —
# скажем, спад по показательной кривой вместо прямой — уехала бы только
# в одну из двух, а следующий читатель поверил бы той, что ближе лежит.


func total_length(note_length: float) -> float:
	## Сколько всего звучит нота вместе с отпусканием.
	return note_length + release
