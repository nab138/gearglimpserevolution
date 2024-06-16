import UIKit
import ARKit
import SceneKit
import SceneKit.ModelIO

class RootViewController: UIViewController, UIGestureRecognizerDelegate, ARSessionDelegate {
    var sceneView: ARSceneView!
    var robotNode: SCNNode!

    var hasPlacedField = false

    var NTHandler: NetworkTablesHandler!

    var statusLabel: PaddedLabel!
    var instructionLabel: PaddedLabel!

    var openSettingsLabel: UILabel!
    
    var frameCounter = 0

    override func loadView() {
        super.loadView()

        sceneView = ARSceneView(frame: UIScreen.main.bounds)
        sceneView.autoenablesDefaultLighting = true
        self.view.addSubview(sceneView)

        instructionLabel = PaddedLabel()
        instructionLabel.font = UIFont.systemFont(ofSize: 18)
        instructionLabel.textColor = UIColor.white
        instructionLabel.backgroundColor = UIColor.darkGray.withAlphaComponent(0.65)
        instructionLabel.text = "Move iPhone to start"
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.layer.cornerRadius = 10
        instructionLabel.layer.masksToBounds = true
        instructionLabel.topInset = 10
        instructionLabel.bottomInset = 10
        instructionLabel.leftInset = 15
        instructionLabel.rightInset = 15
        
        self.view.addSubview(instructionLabel)

        NSLayoutConstraint.activate([
            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        sceneView.session.delegate = self

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        sceneView.session.run(configuration)

        guard let field = sceneView.loadModelFromResources("Field3d_2024") else {
            NSLog("Failed to load field model")
            return
        }
        sceneView.fieldNode = field
        sceneView.fieldNode.scale = SCNVector3(0.05, 0.05, 0.05)
        NSLog("Field loaded successfully")

        if UserDefaults.standard.object(forKey: "fieldVisible") == nil {
            UserDefaults.standard.set(true, forKey: "fieldVisible")
        }

        sceneView.fieldNode.isHidden = !(UserDefaults.standard.bool(forKey: "fieldVisible"))
        sceneView.fieldNode.opacity = UserDefaults.standard.bool(forKey: "fieldTransparent") ? 0.5 : 1.0

        
        // Load the robot, it should be relative to the field. 0,0 should be the center of the field
        if !UserDefaults.standard.bool(forKey: "customRobotSelected") {
            let robotName = UserDefaults.standard.string(forKey: "selectedRobotName") ?? "2024 KitBot"
            loadRobot(name: robotName)
        } else {
            let robotName = UserDefaults.standard.string(forKey: "customRobotName") ?? "Custom Robot"
            if let bookmarkData = UserDefaults.standard.data(forKey: "customRobotBookmarkData") {
                var isStale = false
                do {
                    let bookmarkURL = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                    if isStale {
                        // The bookmark data is stale, so you need to create a new bookmark
                        let newBookmarkData = try bookmarkURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                        UserDefaults.standard.set(newBookmarkData, forKey: "customRobotBookmarkData")
                    }
                    
                    let robotOffset = SCNVector3(
                        UserDefaults.standard.float(forKey: "xOffset"),
                        UserDefaults.standard.float(forKey: "yOffset"),
                        UserDefaults.standard.float(forKey: "zOffset")
                    )
                    let rotationOffset = SCNVector3(
                        UserDefaults.standard.float(forKey: "xRot"),
                        UserDefaults.standard.float(forKey: "yRot"),
                        UserDefaults.standard.float(forKey: "zRot")
                    )
                    let robot = Robot(url: bookmarkURL, name: robotName, positionOffset: robotOffset, rotations: rotationOffset)
                    loadRobot(robot: robot)                    
                } catch {
                    NSLog("Failed to resolve bookmark: \(error)")
                    loadRobot(name: "2024 KitBot")
                }
            } else {
                loadRobot(name: "2024 KitBot")
            }
        }

        sceneView.curContainerDummyNode?.isHidden = true
        
        addGestureRecognizers()
        statusLabel = PaddedLabel()

        statusLabel.text = "NT: Disconnected"
        statusLabel.font = UIFont.systemFont(ofSize: 14)
        statusLabel.textColor = UIColor.white
        statusLabel.backgroundColor = UIColor.red.withAlphaComponent(0.4)
        statusLabel.textAlignment = .center
        statusLabel.layer.cornerRadius = 10
        statusLabel.layer.masksToBounds = true
        statusLabel.sizeToFit()
        statusLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        statusLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        statusLabel.leftInset = 10
        statusLabel.rightInset = 10

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        sceneView.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            statusLabel.heightAnchor.constraint(equalToConstant: 30)
        ])

        NTHandler = NetworkTablesHandler(robotNode: robotNode, statusLabel: statusLabel, sceneView: sceneView)
        NTHandler.connect()


        openSettingsLabel = UILabel()
        openSettingsLabel.font = UIFont.systemFont(ofSize: 18)
        openSettingsLabel.textColor = UIColor.white
        openSettingsLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        openSettingsLabel.text = "Press & Hold to Open Settings!"
        openSettingsLabel.textAlignment = .center // Center the text
        openSettingsLabel.translatesAutoresizingMaskIntoConstraints = false
        openSettingsLabel.layer.cornerRadius = 10
        openSettingsLabel.layer.masksToBounds = true



        if UserDefaults.standard.bool(forKey: "hasOpenedSettings") == false {
            self.view.addSubview(openSettingsLabel)
            NSLayoutConstraint.activate([
                openSettingsLabel.topAnchor.constraint(equalTo: self.view.topAnchor),
                openSettingsLabel.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
                openSettingsLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                openSettingsLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
            ])
        }
    }

    func loadRobot(name: String){
        let robot = Robot.getByName(name)
        loadRobot(robot: robot)
    }

    func loadRobot(robot: Robot){
        guard let robot = sceneView.loadRobot(robot) else {
            NSLog("Failed to load robot model")
            return
        }
        NSLog("Robot loaded successfully")
        robotNode = robot
        if NTHandler != nil {
            NTHandler.setNewRobot(robot: robot)
        }
    }

    // Done to allow rotation and pinch gestures to work simultaneously
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    // This is done to make sure the ARSceneView is resized when the device is rotated
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        sceneView.frame = CGRect(origin: .zero, size: size)
    }

    let serialQueue = DispatchQueue(label: "me.nabdev.gearglimpserev.serialQueue")
    var isProcessing = false

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        serialQueue.async {
            guard !self.isProcessing else { return }
            self.isProcessing = true
            self.sceneView.detectAprilTagsInScene()
            self.isProcessing = false
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        instructionLabel.isHidden = false
        switch camera.trackingState {
            case .notAvailable:
                instructionLabel.text = "Tracking not available"
            case .limited(ARCamera.TrackingState.Reason.initializing):
                instructionLabel.text = "Move phone to start"
            case .limited(ARCamera.TrackingState.Reason.excessiveMotion):
                instructionLabel.text = "Slow down movement"
            case .limited(ARCamera.TrackingState.Reason.insufficientFeatures):
                instructionLabel.text = "More light or texture needed"
            case .limited(ARCamera.TrackingState.Reason.relocalizing):
                instructionLabel.text = "Relocalizing"
            case .limited(_):
                instructionLabel.text = "Move phone to start"
            case .normal:
                instructionLabel.isHidden = true
        }
    }
}