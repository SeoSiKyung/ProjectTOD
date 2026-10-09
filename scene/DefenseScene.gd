extends Node2D

signal DefenseFinished(result: DefenseResult)

@onready var _defenseSceneManager: DefenseSceneManager = $DefenseSceneManager
@onready var _deploymentGridView: DefenseDeploymentGridView = $DeploymentGridView
@onready var _deploymentInfoView: DefenseDeploymentInfoView = $DeploymentInfoView

@onready var _deploymentView: DefenseDeploymentView = %DeploymentView
@onready var _battleHUDView: DefenseBattleHUDView = %BattleHUDView
@onready var _resultView: DefenseResultView = %ResultView

var _deploymentFlowController: DefenseDeploymentFlowController

var _startData: DefenseStartData

var _cp: Unit

var _isBattlePaused: bool = false


#region Lifecycle

func _ready() -> void:
	_InitializeStartData()

	if not _CreateCP():
		return

	_deploymentFlowController = DefenseDeploymentFlowController.new(
		_defenseSceneManager,
		_startData,
		_cp,
		_deploymentGridView,
		_deploymentInfoView,
		_deploymentView,
	)

	_deploymentFlowController.CreateDeploymentGrid()

	if not _defenseSceneManager.Initialize(_startData):
		return

	_deploymentFlowController.InitializeGridView()
	_deploymentFlowController.ConnectSignals()
	_deploymentFlowController.DeploymentFinished.connect(_OnDeploymentFinished)

	_InitializeUI()

	_defenseSceneManager.DefenseFinished.connect(_OnDefenseFinished)

	if not _deploymentFlowController.Start():
		return


func _process(_delta: float) -> void:
	if _defenseSceneManager.GetPhase() == DefenseSceneManager.DefensePhase.BATTLE:
		_UpdateBattleHUD()


func Initialize(startData: DefenseStartData) -> void:
	_startData = startData

#endregion


#region Initialize

func _CreateCP() -> bool:
	var characterData: CharacterData = GameDataManager.GetCharacterData(_startData.commandPostKey)
	if characterData == null:
		push_error(
			"DefenseScene: CP CharacterData를 찾을 수 없습니다. key: " + str(_startData.commandPostKey)
		)
		return false

	if characterData.characterType != CharacterData.CharacterType.COMMAND_POST:
		push_error("DefenseScene: COMMAND_POST 타입이 아닙니다.")
		return false

	var cp: Unit = UnitFactory.Create(characterData)
	if cp == null:
		return false

	cp.name = "CP"
	cp.playerControllable = false
	cp.moveSpeed = 0

	if not _defenseSceneManager.BindCP(cp):
		cp.free()
		return false

	_cp = cp
	add_child(_cp)

	return true


func _InitializeStartData() -> void:
	if _startData != null:
		return

	_startData = DefenseStartData.new()
	_startData.cycle = 1
	_startData.population = 100

	_startData.commandPostKey = 20000

	_startData.installableCountByCharacterKey[500] = 2
	_startData.installableCountByCharacterKey[501] = 2
	_startData.installableCountByCharacterKey[750] = 2
	_startData.installableCountByCharacterKey[751] = 2

	_startData.availableMercenaryKeys = [0, 1, 2]


func _InitializeUI() -> void:
	_battleHUDView.pause_pressed.connect(_OnPauseButtonPressed)
	_resultView.Confirmed.connect(_OnResultConfirmed)

#endregion


#region Battle

func _OnDeploymentFinished() -> void:
	_battleHUDView.ShowBattle()
	_UpdateBattleHUD()


func _OnPauseButtonPressed() -> void:
	if _isBattlePaused:
		_defenseSceneManager.ResumeBattle()
		_isBattlePaused = false
	else:
		_defenseSceneManager.PauseBattle()
		_isBattlePaused = true

	_battleHUDView.SetPaused(_isBattlePaused)


func _OnDefenseFinished(result: DefenseResult) -> void:
	_isBattlePaused = false
	_battleHUDView.SetPaused(false)
	_battleHUDView.SetPauseDisabled(true)
	_battleHUDView.HideBattle()
	_resultView.ShowResult(result)


func _UpdateBattleHUD() -> void:
	_battleHUDView.UpdateBattleTime(_defenseSceneManager.GetElapsedTimeMs())
	_battleHUDView.UpdateCP(
		_defenseSceneManager.GetCPCurrentHp(),
		_defenseSceneManager.GetCPMaxHp(),
		_defenseSceneManager.GetCPCurrentMp(),
		_defenseSceneManager.GetCPMaxMp(),
	)
	_battleHUDView.UpdatePopulation(
		_defenseSceneManager.GetRecruitedPopulation(),
		_defenseSceneManager.GetSurvivingPopulation(),
		_defenseSceneManager.GetDeadPopulation(),
	)

#endregion


#region Result Events

func _OnResultConfirmed(result: DefenseResult) -> void:
	DefenseFinished.emit(result)

#endregion
