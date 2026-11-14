extends Node
## Autoload "Ads": every ad in the game goes through here, so the rules that keep
## players happy live in one place.
##
## Placements
##   rewarded:      "hint", "revive", "double", "coins"  (always the player's choice)
##   interstitial:  between levels only, with strict frequency caps (see should_interstitial)
##
## Backends
##   - Test mode (default, and always on web/desktop): shows a clearly labelled fake ad.
##   - AdMob: used automatically on Android once the AdMob plugin is in res://addons/admob
##     and REAL_IDS below are filled in. Until then Google's public test IDs are used.

signal ad_finished(placement: String, rewarded: bool)
signal notice(text: String)
signal _closed

# ---- AdMob ids (replace with your own from admob.google.com before release)
const TEST_IDS := {
	"app": "ca-app-pub-3940256099942544~3347511713",
	"rewarded": "ca-app-pub-3940256099942544/5224354917",
	"interstitial": "ca-app-pub-3940256099942544/1033173712",
}
const REAL_IDS := {
	"app": "ca-app-pub-9206798746776764~6129473150",
	"rewarded": "ca-app-pub-9206798746776764/2762887874",
	"interstitial": "ca-app-pub-9206798746776764/2383613928",
}

# ---- player-friendly rules
const INTERSTITIAL_FROM_LEVEL := 8       # new players never see forced ads
const INTERSTITIAL_EVERY := 3            # at most once every 3 completed levels
const INTERSTITIAL_GAP_SEC := 240.0      # and never twice within 4 minutes
const AFTER_REWARDED_GAP_SEC := 180.0    # skip if they just chose to watch one
const COIN_ADS_PER_DAY := 5
const COINS_PER_AD := 40

var _levels_since := 0
var _last_interstitial := -1e9
var _last_rewarded := -1e9
var _busy := false
var _coin_ads_date := ""
var _coin_ads_count := 0

var _admob := false          # real AdMob available (Android build with the plugin)
var _rewarded_ad = null
var _inter_ad = null
var _loading_r := false
var _loading_i := false
var _earned := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load("user://ads.cfg") == OK:
		_coin_ads_date = str(cfg.get_value("ads", "coin_date", ""))
		_coin_ads_count = int(cfg.get_value("ads", "coin_count", 0))
	if OS.get_name() == "Android" and Engine.has_singleton("PoingGodotAdMob"):
		_admob = true
		_request_consent()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


## Debug builds always use Google's test ads so we never click our own real ads.
func _unit(kind: String) -> String:
	if OS.is_debug_build() or REAL_IDS[kind] == "":
		return TEST_IDS[kind]
	return REAL_IDS[kind]


func is_test_mode() -> bool:
	return not _admob


# ================================================================ rewarded

## Shows a rewarded ad. Returns true only if the player watched it to the end.
func rewarded(placement: String) -> bool:
	if _busy:
		return false
	_busy = true
	var ok: bool = await _show(placement, true)
	_busy = false
	if ok:
		_last_rewarded = _now()
	ad_finished.emit(placement, ok)
	return ok


func coin_ads_left() -> int:
	if _coin_ads_date != _today():
		return COIN_ADS_PER_DAY
	return maxi(0, COIN_ADS_PER_DAY - _coin_ads_count)


func note_coin_ad() -> void:
	if _coin_ads_date != _today():
		_coin_ads_date = _today()
		_coin_ads_count = 0
	_coin_ads_count += 1
	var cfg := ConfigFile.new()
	cfg.set_value("ads", "coin_date", _coin_ads_date)
	cfg.set_value("ads", "coin_count", _coin_ads_count)
	cfg.save("user://ads.cfg")


# ================================================================ interstitial

## Call after every completed campaign level; decides whether a break ad is OK right now.
func level_completed() -> void:
	_levels_since += 1


func should_interstitial(next_level: int) -> bool:
	return next_level > INTERSTITIAL_FROM_LEVEL \
		and _levels_since >= INTERSTITIAL_EVERY \
		and _now() - _last_interstitial >= INTERSTITIAL_GAP_SEC \
		and _now() - _last_rewarded >= AFTER_REWARDED_GAP_SEC


## Shows a break ad if the rules allow it. Always safe to await.
func maybe_interstitial(next_level: int) -> void:
	if _busy or not should_interstitial(next_level):
		return
	_busy = true
	await _show("break", false)
	_busy = false
	_levels_since = 0
	_last_interstitial = _now()


# ================================================================ AdMob backend

## Google's consent form (shown only where the law requires it, e.g. EU/UK), then start the SDK.
func _request_consent() -> void:
	UserMessagingPlatform.consent_information.update(ConsentRequestParameters.new(),
		_on_consent_updated, _on_consent_error)


func _on_consent_updated() -> void:
	var info := UserMessagingPlatform.consent_information
	if info.get_is_consent_form_available() 			and info.get_consent_status() == ConsentInformation.ConsentStatus.REQUIRED:
		UserMessagingPlatform.load_consent_form(_on_consent_form_loaded, _on_consent_error)
	else:
		_init_sdk()


func _on_consent_form_loaded(form: ConsentForm) -> void:
	form.show(_on_consent_error)


func _on_consent_error(_error: FormError = null) -> void:
	_init_sdk()


func _init_sdk() -> void:
	var done := OnInitializationCompleteListener.new()
	done.on_initialization_complete = func(_status: InitializationStatus) -> void:
		_load_rewarded()
		_load_interstitial()
	MobileAds.set_request_configuration(RequestConfiguration.new())
	MobileAds.initialize(done)


func _closed_callbacks(kind: String) -> FullScreenContentCallback:
	var cb := FullScreenContentCallback.new()
	cb.on_ad_dismissed_full_screen_content = func() -> void:
		_after_show(kind)
	cb.on_ad_failed_to_show_full_screen_content = func(_error: AdError) -> void:
		_after_show(kind)
	return cb


func _after_show(kind: String) -> void:
	if kind == "rewarded":
		if _rewarded_ad:
			_rewarded_ad.destroy()
		_rewarded_ad = null
		_load_rewarded()
	else:
		if _inter_ad:
			_inter_ad.destroy()
		_inter_ad = null
		_load_interstitial()
	_closed.emit()


func _load_rewarded() -> void:
	if _loading_r or _rewarded_ad != null:
		return
	_loading_r = true
	var cb := RewardedAdLoadCallback.new()
	cb.on_ad_loaded = func(ad: RewardedAd) -> void:
		_loading_r = false
		_rewarded_ad = ad
		ad.full_screen_content_callback = _closed_callbacks("rewarded")
	cb.on_ad_failed_to_load = func(_error: LoadAdError) -> void:
		_loading_r = false
	RewardedAdLoader.new().load(_unit("rewarded"), AdRequest.new(), cb)


func _load_interstitial() -> void:
	if _loading_i or _inter_ad != null:
		return
	_loading_i = true
	var cb := InterstitialAdLoadCallback.new()
	cb.on_ad_loaded = func(ad: InterstitialAd) -> void:
		_loading_i = false
		_inter_ad = ad
		ad.full_screen_content_callback = _closed_callbacks("interstitial")
	cb.on_ad_failed_to_load = func(_error: LoadAdError) -> void:
		_loading_i = false
	InterstitialAdLoader.new().load(_unit("interstitial"), AdRequest.new(), cb)


## Waits briefly for a video if one is still loading.
func _ensure_rewarded() -> bool:
	_load_rewarded()
	var waited := 0.0
	while _rewarded_ad == null and waited < 4.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	return _rewarded_ad != null


func _admob_rewarded() -> bool:
	_earned = false
	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = func(_item: RewardedItem) -> void:
		_earned = true
	_rewarded_ad.show(listener)
	await _closed
	return _earned


func _admob_interstitial() -> bool:
	_inter_ad.show()
	await _closed
	return false


# ================================================================ test-mode ad

func _show(placement: String, reward: bool) -> bool:
	if _admob and not reward and _inter_ad == null:
		_load_interstitial()     # nothing ready: skip this break, never make the player wait
		return false
	if _admob and reward and not await _ensure_rewarded():
		notice.emit("No video available right now")
		return false
	var music_was := Sfx.music_on
	if music_was:
		Sfx.set_music(false)
	var ok: bool
	if _admob:
		if reward:
			ok = await _admob_rewarded()
		else:
			ok = await _admob_interstitial()
	else:
		ok = await _test_ad(placement, reward)
	if music_was:
		Sfx.set_music(true)
	return ok


## Full-screen stand-in for a real ad so the whole flow can be tested anywhere.
func _test_ad(placement: String, reward: bool) -> bool:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 26)
	bg.add_child(box)
	var title := Label.new()
	title.text = "TEST AD"
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var info := Label.new()
	info.text = ("Rewarded video - %s" % placement) if reward else "Break between levels"
	info.add_theme_font_size_override("font_size", 30)
	info.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(info)
	var count := Label.new()
	count.add_theme_font_size_override("font_size", 90)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(count)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(320, 96)
	close.add_theme_font_size_override("font_size", 36)
	close.visible = false
	box.add_child(close)
	box.reset_size()
	box.position = (bg.get_viewport_rect().size - box.size) / 2.0
	var secs := 3 if reward else 2
	for s in range(secs, 0, -1):
		count.text = str(s)
		await get_tree().create_timer(1.0).timeout
	count.text = "Reward earned!" if reward else ""
	close.visible = true
	box.reset_size()
	box.position = (bg.get_viewport_rect().size - box.size) / 2.0
	await close.pressed
	layer.queue_free()
	return reward
