extends Control

var state_machine := load("res://core/ui/menus/global_state_machine.tres") as StateMachine
var installer := load("res://core/systems/installer/installer.tres") as Installer
var disks := installer.get_available_disks()

@onready var tree := $%Tree
@onready var next_button := $%NextButton
@onready var yes_button := $%YesButton
@onready var no_button := $%NoButton
@onready var http := $%HTTPFileDownloader as HTTPFileDownloader


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Listen for next button pressed
	next_button.pressed.connect(_on_next_pressed)
	
	# Only enable the next button when an item is selected
	var on_selected := func():
		next_button.disabled = false
	tree.item_selected.connect(on_selected)
	
	# Configure the tree view
	var root := tree.create_item() as TreeItem
	var columns := PackedStringArray(["Name", "Model", "Size"])
	for i in range(columns.size()):
		var column_name := columns[i]
		tree.set_column_title(i, column_name)
		tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
	
	for disk in disks:
		var disk_item := root.create_child()
		disk_item.set_text(0, disk.name)
		disk_item.set_text(1, disk.model)
		disk_item.set_text(2, disk.size)
		disk_item.set_metadata(0, disk)

## Invoked when the Next button is pressed
func _on_next_pressed() -> void:
	var item := tree.get_selected() as TreeItem
	if not item:
		push_warning("No item was selected!")
		return
	
	# Get the disk from the selected tree item
	var disk := item.get_metadata(0) as Installer.Disk
	print("Selected disk: " + disk.path)

	# Check if the given disk already has an installation or not
	var dialog := get_tree().get_first_node_in_group("dialog") as Dialog
	if disk.install_found:
		var msg := "WARNING: " + disk.name + " appears to have another system deployed, " + \
			"would you like to repair the install?"
		dialog.open(msg, "Yes", "No")
		var should_repair := await dialog.choice_selected as bool
		
		if should_repair:
			_start_repair(disk)
			return

	# Warn the user before bootstrapping
	var msg := "WARNING: " + disk.name + " will now be formatted. All data on the disk will be lost." + \
		" Do you wish to proceed?"
	dialog.open(msg, "No", "Yes")
	var should_stop := await dialog.choice_selected as bool
	if should_stop:
		next_button.grab_focus.call_deferred()
		return
	
	_start_dd(disk)

# Perform the dd
func _start_dd(disk: Installer.Disk) -> void:
	print("DD to disk")
	var dialog := get_tree().get_first_node_in_group("dialog") as Dialog
	var progress := get_tree().get_first_node_in_group("progress_dialog") as ProgressDialog

	# Set up the progress bar
	progress.value = 0
	var on_progress := func(percent: float):
		progress.value = percent * 100
	installer.dd_progressed.connect(on_progress)
	progress.open("Flashing image to disk")

	# Wait for the bootstrapping to complete
	var err := await installer.dd_image(disk)
	if installer.flash_finished:
		installer.dd_progressed.disconnect(on_progress)
		progress.close()
		if err != OK:
			var err_msg := installer.last_error
			dialog.open("DD command failed:\n" + err_msg, "OK", "Cancel")
			await dialog.choice_selected
			next_button.grab_focus.call_deferred()
			return
		# Switch menus
		var completed_state := load("res://core/ui/menus/completed_install_state.tres")
		state_machine.set_state([completed_state])
# Perform the bootstrapping

func _start_bootstrap(disk: Installer.Disk) -> void:
	print("Bootstrapping disk")
	var dialog := get_tree().get_first_node_in_group("dialog") as Dialog
	var progress := get_tree().get_first_node_in_group("progress_dialog") as ProgressDialog

	# Set up the progress bar
	progress.value = 0
	var on_progress := func(percent: float):
		progress.value = percent * 100
	installer.bootstrap_progressed.connect(on_progress)
	progress.open("Bootstrapping disk")

	# Wait for the bootstrapping to complete
	var err := await installer.bootstrap(disk)
	installer.bootstrap_progressed.disconnect(on_progress)
	progress.close()
	if err != OK:
		var err_msg := installer.last_error
		dialog.open("System bootstrap failed:\n" + err_msg, "OK", "Cancel")
		await dialog.choice_selected
		next_button.grab_focus.call_deferred()
		return
	
	state_machine.set_state([])
	_start_post_bootstrap()


# Perform a repair
func _start_repair(disk: Installer.Disk) -> void:
	print("Repairing install")
	var dialog := get_tree().get_first_node_in_group("dialog") as Dialog
	var progress := get_tree().get_first_node_in_group("progress_dialog") as ProgressDialog
	
	# Set up the progress bar
	progress.value = 0
	var on_progress := func(percent: float):
		progress.value = percent * 100
	installer.repair_progressed.connect(on_progress)
	progress.open("Repairing installation")
	
	# Wait for the repair to complete
	var err := await installer.repair_install(disk)
	installer.repair_progressed.disconnect(on_progress)
	progress.close()
	if err != OK:
		dialog.open("Failed to repair installation:\n" + installer.last_error, "OK", "Cancel")
		await dialog.choice_selected
		next_button.grab_focus.call_deferred()
		return
	
	state_machine.set_state([])
	_start_post_bootstrap()


# Perform the post-bootstrapping steps
func _start_post_bootstrap() -> void:
	# Get the dialog node
	var dialog := get_tree().get_first_node_in_group("dialog") as Dialog
	var progress := get_tree().get_first_node_in_group("progress_dialog") as ProgressDialog
	
	# Copy over all network configuration from the live session to the system
	await installer.copy_network_config()
	
	# Grab the steam bootstrap for first boot
	var url := "https://steamdeck-packages.steamos.cloud/archlinux-mirror/jupiter-main/os/x86_64/steam-jupiter-stable-1.0.0.76-1-x86_64.pkg.tar.zst"
	var tmp_pkg := "/tmp/package.pkg.tar.zst"
	var tmp_file := "/tmp/bootstraplinux_ubuntu12_32.tar.xz"
	var destination := "/tmp/frzr_root/etc/first-boot/"
	if not DirAccess.dir_exists_absolute(destination):
		DirAccess.make_dir_recursive_absolute(destination)

	http.download_file = tmp_pkg
	if http.request(url) != OK:
		var msg := "Failed to download steam bootstrap"
		dialog.open(msg, "Retry", "Cancel")
		var should_retry := await dialog.choice_selected as bool

	# Show a progress dialog for the download
	progress.value = 0
	progress.open("Downloading Steam bootstrap package")
	var on_progress := func(percent: float):
		progress.value = percent * 100
	http.progressed.connect(on_progress)
	var on_cancelled := func():
		http.cancel_request()
	progress.cancelled.connect(on_cancelled, CONNECT_ONE_SHOT)

	await http.request_completed
	http.progressed.disconnect(on_progress)
	progress.close()
	print("Download completed")
	
	await Command.new("bash", ["-c", "tar -I zstd -xvf '" + tmp_pkg + "' usr/lib/steam/bootstraplinux_ubuntu12_32.tar.xz -O > '" + tmp_file + "'"])
	await Command.new("mv", [tmp_file, destination]).execute()
	await Command.new("rm", [tmp_pkg]).execute()

	# Switch menus
	var installer_options_state := load("res://core/ui/menus/installer_options_state.tres")
	state_machine.set_state([installer_options_state])
