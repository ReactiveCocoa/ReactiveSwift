import UIKit
import PlaygroundSupport
import ReactiveSwift
import Result

class Example: NSObject {

    override init() {
        super.init()

        let viewModel = ExampleViewModel()

        let tableViewController = ExampleTableViewController(viewModel: viewModel)
        let navigationController = UINavigationController(rootViewController: tableViewController)
        navigationController.view.translatesAutoresizingMaskIntoConstraints = true
        navigationController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        PlaygroundPage.current.needsIndefiniteExecution = true
        PlaygroundPage.current.liveView = navigationController
    }
}

class ExampleViewModel {
    private let strings = MutableProperty<[String]>([])
    let snapshots: SignalProducer<Snapshot<[[String]], SectionedChangeset>, NoError>

    init() {
        let grouped = strings.map { strings -> [[String]] in
            var groups: [Character: [String]] = [:]

            for string in strings {
                let key = string.characters.first ?? Character("\0")
                if groups[key] == nil {
                    groups[key] = []
                }

                groups[key]!.append(string)
            }

            return groups
                .sorted(by: { $0.key < $1.key })
                .map { $0.value.sorted { $0.compare($1) == .orderedAscending } }
        }

        snapshots = grouped.producer
            .diff(sectionIdentifier: { $0.first?.characters.first ?? Character("\0") },
                  areSectionsEqual: { $0.isEmpty && $1.isEmpty || $0[0].characters.first == $1[0].characters.first },
                  elementIdentifier: { $0 },
                  areElementsEqual: ==)
    }

    func insert(_ items: [String]) {
        strings.modify { strings in
            strings.append(contentsOf: items)
        }
    }

    func remove(_ items: [String]) {
        strings.modify { strings in
            let indices = items.flatMap(strings.index(of:)).sorted(by: >)
            for index in indices {
                strings.remove(at: index)
            }
        }
    }
}

class ExampleTableViewController: UITableViewController {
    var items: [[String]] = []
    var isAnimating: Bool = false

    fileprivate var deleteButtonItem: UIBarButtonItem!
    fileprivate let viewModel: ExampleViewModel

    init(viewModel: ExampleViewModel) {
        self.viewModel = viewModel
        super.init(style: .plain)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.allowsSelectionDuringEditing = true
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.keyboardDismissMode = .interactive
        tableView.dataSource = self
        tableView.delegate = self
        tableView.reloadData()

        deleteButtonItem = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(deleteItems))
        deleteButtonItem.tintColor = .red
        navigationItem.leftBarButtonItem = editButtonItem

        let textField = UITextField()
        textField.delegate = self
        textField.borderStyle = .roundedRect
        tableView.tableFooterView = UIView()
        tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        tableView.tableHeaderView!.backgroundColor = UIColor(white: 0.80, alpha: 1.0)
        tableView.tableHeaderView!.addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: tableView.tableHeaderView!.layoutMarginsGuide.topAnchor),
            textField.bottomAnchor.constraint(equalTo: tableView.tableHeaderView!.layoutMarginsGuide.bottomAnchor),
            textField.leadingAnchor.constraint(equalTo: tableView.tableHeaderView!.layoutMarginsGuide.leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: tableView.tableHeaderView!.layoutMarginsGuide.trailingAnchor),
        ])

        bind(viewModel.snapshots)
    }

    private func bind(_ snapshots: SignalProducer<Snapshot<[[String]], SectionedChangeset>, NoError>) {
        snapshots.startWithValues { [weak tableView] snapshot in
            print("\(Date())\n\(snapshot.changeset.debugDescription)\n\n")

            guard let tableView = tableView else { return }

            CATransaction.begin()
            tableView.beginUpdates()
            self.isAnimating = true

            func apply(_ tableView: UITableView, for mutatedSections: [Int: SectionedChangeset.MutatedSection]) {
                for (offset, section) in mutatedSections {
                    print("applying section delta for section \(section.source) -> \(offset)")

                    tableView.deleteRows(at: section.changeset.removals.map { [section.source, $0] }, with: .left)
                    tableView.insertRows(at: section.changeset.inserts.map { [offset, $0] }, with: .top)

                    var reloadForMoves = [IndexPath]()
                    for (destination, move) in section.changeset.moves {
                        tableView.moveRow(at: [section.source, move.source], to: [offset, destination])

                        if move.isMutated {
                            reloadForMoves.append([section.source, move.source])
                        }
                    }

                    tableView.reloadRows(at: reloadForMoves, with: .fade)
                    tableView.reloadRows(at: section.changeset.mutations.map { [section.source, $0] }, with: .fade)
                }
            }

            if !snapshot.changeset.sections.removals.isEmpty {
                tableView.deleteSections(snapshot.changeset.sections.removals, with: .left)
            }

            if !snapshot.changeset.sections.inserts.isEmpty {
                tableView.insertSections(snapshot.changeset.sections.inserts, with: .top)
            }

            apply(tableView, for: snapshot.changeset.mutatedSections)

            for (destination, move) in snapshot.changeset.sections.moves {
                tableView.moveSection(move.source, toSection: destination)
            }

            self.items = snapshot.elements
            tableView.endUpdates()
            CATransaction.setCompletionBlock {
                self.isAnimating = false
            }
            CATransaction.commit()
        }
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        tableView.endEditing(true)

        super.setEditing(editing, animated: animated)
        navigationItem.rightBarButtonItem = editing ? deleteButtonItem : nil
    }

    @objc func deleteItems() {
        guard isEditing else { return }
        let indexPaths = tableView.indexPathsForSelectedRows
        setEditing(false, animated: true)

        if let indexPaths = indexPaths {
            let items = indexPaths.map { self.items[$0.section][$0.row] }
            self.viewModel.remove(items)
        }
    }
}

extension ExampleTableViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard !isAnimating else {
            print("The table view is animating.")
            return false
        }

        if let string = textField.text, !string.isEmpty {
            viewModel.insert([string])
            textField.text = nil
        }

        return false
    }
}

extension ExampleTableViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel!.text = items[indexPath.section][indexPath.row]
        return cell
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items[section].count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return (items[section].first?.characters.first).map { String($0) }
    }
}

extension ExampleTableViewController {
    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        return [
            UITableViewRowAction(style: .destructive, title: "Delete") { _, indexPath in
                guard !self.isAnimating else {
                    print("The table view is animating.")
                    return
                }

                let item = self.items[indexPath.section][indexPath.row]
                self.viewModel.remove([item])
            }
        ]
    }
}

let example = Example()
Thread.current.threadDictionary["heh"] = example
