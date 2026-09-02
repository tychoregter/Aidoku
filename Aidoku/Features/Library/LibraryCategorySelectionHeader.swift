import SwiftUI
import UIKit

protocol LibraryCategorySelectionHeaderDelegate: AnyObject {
    func optionSelected(_ indexPath: IndexPath)
}

private struct LibraryCategoryPillsView: View {
    let options: [(title: String, indexPath: IndexPath, locked: Bool)]
    let selected: IndexPath
    let onSelect: (IndexPath) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options, id: \.indexPath) { option in
                    let active = selected == option.indexPath
                    Button { onSelect(option.indexPath) } label: {
                        let label = HStack(spacing: 5) {
                            if option.locked { Image(systemName: "lock.fill") }
                            Text(option.title)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(active ? Color.white : Color.primary)
                        if #available(iOS 26.0, *) {
                            label.glassEffect(active ? .regular.tint(.accentColor) : .regular)
                        } else {
                            label.background(RoundedRectangle(cornerRadius: 100).fill(Color(uiColor: active ? .tintColor : .secondarySystemFill)))
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .scrollClipDisabledPlease()
        .padding(.vertical, 8)
    }
}

class LibraryCategorySelectionHeader: UICollectionReusableView {
    weak var delegate: LibraryCategorySelectionHeaderDelegate?

    struct Section { var title: String?; var options: [String] = [] }
    var options: [Section] = [] { didSet { updateContent() } }
    var lockedOptions: [IndexPath] = [] { didSet { updateContent() } }
    private var selectedIndexPath = IndexPath(row: 0, section: 0)
    private var hostedView: UIView?
    private var hostingController: UIViewController?

    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSelectedOption(_ indexPath: IndexPath) {
        guard selectedIndexPath != indexPath else { return }
        selectedIndexPath = indexPath
        updateContent()
        delegate?.optionSelected(indexPath)
    }

    private func updateContent() {
        let flattened = options.enumerated().flatMap { section, value in
            value.options.enumerated().map { row, title in
                (title: title, indexPath: IndexPath(row: row, section: section), locked: lockedOptions.contains(IndexPath(row: row, section: section)))
            }
        }
        let controller = UIHostingController(
            rootView: LibraryCategoryPillsView(options: flattened, selected: selectedIndexPath) { [weak self] indexPath in
                self?.setSelectedOption(indexPath)
            }
        )
        hostedView?.removeFromSuperview()
        let hostedView = controller.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        self.hostedView = hostedView
        self.hostingController = controller
    }
}
