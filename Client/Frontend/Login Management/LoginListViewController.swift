/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import SnapKit
import Storage
import Shared

private struct LoginListUX {
    static let RowHeight: CGFloat = 58
    static let SearchHeight: CGFloat = 58
    static let selectionButtonFont = UIFont.systemFontOfSize(16)
    static let selectionButtonTextColor = UIColor.whiteColor()
    static let selectionButtonBackground = UIConstants.HighlightBlue
}

private extension UITableView {
    var allIndexPaths: [NSIndexPath] {
        return (0..<self.numberOfSections).flatMap { sectionNum in
            (0..<self.numberOfRowsInSection(sectionNum)).map { NSIndexPath(forRow: $0, inSection: sectionNum) }
        }
    }
}

private let LoginCellIdentifier = "LoginCell"

class LoginListViewController: UIViewController {

    private lazy var loginSelectionController: ListSelectionController = {
        return ListSelectionController(tableView: self.tableView)
    }()

    private lazy var loginFaviconLoader: LoginFaviconLoader = {
        let loader = LoginFaviconLoader(profile: self.profile)
        loader.delegate = self
        return loader
    }()

    private lazy var loginDataSource: LoginCursorDataSource = {
        return LoginCursorDataSource()
    }()

    private let profile: Profile

    private let searchView = SearchInputView()

    private var activeLoginQuery: Success?

    // Titles for selection/deselect buttons
    private let deselectAllTitle = NSLocalizedString("Deselect All", tableName: "LoginManager", comment: "Title for deselecting all selected logins")
    private let selectAllTitle = NSLocalizedString("Select All", tableName: "LoginManager", comment: "Title for selecting all logins")

    private lazy var selectionButton: UIButton = {
        let button = UIButton()
        button.titleLabel?.font = LoginListUX.selectionButtonFont
        button.setTitle(self.selectAllTitle, forState: .Normal)
        button.setTitleColor(LoginListUX.selectionButtonTextColor, forState: .Normal)
        button.backgroundColor = LoginListUX.selectionButtonBackground
        button.addTarget(self, action: "SELdidTapSelectionButton", forControlEvents: .TouchUpInside)
        return button
    }()

    private var selectionButtonHeightConstraint: Constraint?
    private var selectedIndexPaths = [NSIndexPath]()

    private let tableView = UITableView()

    weak var settingsDelegate: SettingsDelegate?

    init(profile: Profile) {
        self.profile = profile
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let notificationCenter = NSNotificationCenter.defaultCenter()
        notificationCenter.addObserver(self, selector: Selector("SELonProfileDidFinishSyncing"), name: NotificationProfileDidFinishSyncing, object: nil)

        automaticallyAdjustsScrollViewInsets = false
        self.view.backgroundColor = UIColor.whiteColor()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .Edit, target: self, action: "SELedit")

        self.title = NSLocalizedString("Logins", tableName: "LoginManager", comment: "Title for Logins List View screen")

        searchView.delegate = self
        tableView.registerClass(LoginTableViewCell.self, forCellReuseIdentifier: LoginCellIdentifier)

        view.addSubview(searchView)
        view.addSubview(tableView)
        view.addSubview(selectionButton)

        searchView.snp_makeConstraints { make in
            make.top.equalTo(snp_topLayoutGuideBottom).constraint
            make.left.right.equalTo(self.view)
            make.height.equalTo(LoginListUX.SearchHeight)
        }

        tableView.snp_makeConstraints { make in
            make.top.equalTo(searchView.snp_bottom)
            make.left.right.equalTo(self.view)
            make.bottom.equalTo(self.selectionButton.snp_top)
        }

        selectionButton.snp_makeConstraints { make in
            make.left.right.bottom.equalTo(self.view)
            make.top.equalTo(self.tableView.snp_bottom)
            make.bottom.equalTo(self.view)
            selectionButtonHeightConstraint = make.height.equalTo(0).constraint
        }
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        tableView.accessibilityIdentifier = "Login List"
        tableView.dataSource = loginDataSource
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.delegate = self
        tableView.tableFooterView = UIView()

        KeyboardHelper.defaultHelper.addDelegate(self)

        // If we are editing the search view, use the search term query instead
        if searchView.isEditing {
            searchLoginsWithText(searchView.inputField.text ?? "")
        } else {
            activeLoginQuery = profile.logins.getAllLogins().bindQueue(dispatch_get_main_queue()) { result in
                self.loginDataSource.cursor = result.successValue
                self.tableView.reloadData()

                // Check to see if the logins have favicons. If so, use them, if not, fetch away.
                if let logins = result.successValue?.asArray() {

                    func haveFaviconForLogin(login: Login) -> Bool {
                        return true
                    }

                    func faviconsForLogin(login: Login) -> [Favicon] {
                        return []
                    }

                    // Fetch favicons we need
                    let faviconsToFetch = logins.filter { !haveFaviconForLogin($0) }
                    self.loginFaviconLoader.loadFaviconsForLogins(faviconsToFetch)

                    // Grab favicons we have
                    let faviconsWeHave = logins.filter(haveFaviconForLogin)
                    faviconsWeHave.forEach { login in
                        self.loginDataSource.loginFaviconMap[login] = faviconsForLogin(login)
                    }
                }
                return succeed()
            }
        }
    }

    func toggleDeleteBarButton() {
        // Show delete bar button item if we have selected any items
        if loginSelectionController.selectedCount > 0 {
            if (navigationItem.rightBarButtonItem == nil) {
                navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Delete", style: .Plain, target: self, action: "SELdelete")
                navigationItem.rightBarButtonItem?.tintColor = UIColor.redColor()
            }
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    func toggleSelectionTitle() {
        if loginSelectionController.selectedCount == loginDataSource.cursor?.count {
            selectionButton.setTitle(deselectAllTitle, forState: .Normal)
        } else {
            selectionButton.setTitle(selectAllTitle, forState: .Normal)
        }
    }

    deinit {
        let notificationCenter = NSNotificationCenter.defaultCenter()
        notificationCenter.removeObserver(self, name: NotificationProfileDidFinishSyncing, object: nil)
    }
}

// MARK: - Selectors
extension LoginListViewController {

    func SELonProfileDidFinishSyncing() {
        profile.logins.getAllLogins().uponQueue(dispatch_get_main_queue()) { result in
            self.loginDataSource.cursor = result.successValue
            self.tableView.reloadData()
        }
    }
}

// MARK: - Selectors
extension LoginListViewController {

    func SELedit() {
        navigationItem.rightBarButtonItem = nil
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .Cancel, target: self, action: "SELcancel")
        selectionButtonHeightConstraint?.updateOffset(UIConstants.ToolbarHeight)
        self.view.layoutIfNeeded()
        tableView.setEditing(true, animated: true)
    }

    func SELcancel() {
        // Update selection and select all button
        loginSelectionController.deselectAll()
        toggleSelectionTitle()
        selectionButtonHeightConstraint?.updateOffset(0)
        self.view.layoutIfNeeded()

        tableView.setEditing(false, animated: true)
        navigationItem.leftBarButtonItem = nil
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .Edit, target: self, action: "SELedit")
    }

    func SELdelete() {
        profile.logins.hasSyncedLogins().uponQueue(dispatch_get_main_queue()) { yes in
            let deleteAlert = UIAlertController.deleteLoginAlertWithDeleteCallback({ [unowned self] _ in
                // Delete here
                let guidsToDelete = self.loginSelectionController.selectedIndexPaths.map { indexPath in
                    self.loginDataSource.loginAtIndexPath(indexPath).guid
                }

                self.profile.logins.removeLoginsWithGUIDs(guidsToDelete) >>> {
                    self.activeLoginQuery = self.profile.logins.getAllLogins().bindQueue(dispatch_get_main_queue()) { result in
                        // Cancel out of editing
                        self.SELcancel()

                        self.loginDataSource.cursor = result.successValue
                        self.tableView.reloadData()
                        return succeed()
                    }
                }
            }, hasSyncedLogins: yes.successValue ?? true)

            self.presentViewController(deleteAlert, animated: true, completion: nil)
        }
    }

    func SELdidTapSelectionButton() {
        // If we haven't selected everything yet, select all
        if loginSelectionController.selectedCount < loginDataSource.cursor?.count {
            // Find all unselected indexPaths
            let unselectedPaths = tableView.allIndexPaths.filter { indexPath in
                return !loginSelectionController.indexPathIsSelected(indexPath)
            }
            loginSelectionController.selectIndexPaths(unselectedPaths)
            unselectedPaths.forEach { indexPath in
                self.tableView.selectRowAtIndexPath(indexPath, animated: true, scrollPosition: .None)
            }
        }

        // If everything has been selected, deselect all
        else {
            loginSelectionController.deselectAll()
            tableView.allIndexPaths.forEach { indexPath in
                self.tableView.deselectRowAtIndexPath(indexPath, animated: true)
            }
        }

        toggleSelectionTitle()
        toggleDeleteBarButton()
    }
}

// MARK: - UITableViewDelegate
extension LoginListViewController: UITableViewDelegate {

    func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        // Force the headers to be hidden
        return 0
    }

    func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        return LoginListUX.RowHeight
    }

    func tableView(tableView: UITableView, editingStyleForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCellEditingStyle {
        return .None
    }

    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        if tableView.editing {
            loginSelectionController.selectIndexPath(indexPath)
            toggleSelectionTitle()
            toggleDeleteBarButton()
        } else {
            tableView.deselectRowAtIndexPath(indexPath, animated: true)
            let login = loginDataSource.loginAtIndexPath(indexPath)
            let detailViewController = LoginDetailViewController(profile: profile, login: login)
            detailViewController.settingsDelegate = settingsDelegate
            navigationController?.pushViewController(detailViewController, animated: true)
        }
    }

    func tableView(tableView: UITableView, didDeselectRowAtIndexPath indexPath: NSIndexPath) {
        if tableView.editing {
            loginSelectionController.deselectIndexPath(indexPath)
            toggleSelectionTitle()
            toggleDeleteBarButton()
        }
    }
}

// MARK: - KeyboardHelperDelegate
extension LoginListViewController: KeyboardHelperDelegate {

    func keyboardHelper(keyboardHelper: KeyboardHelper, keyboardWillShowWithState state: KeyboardState) {
        let coveredHeight = state.intersectionHeightForView(tableView)
        tableView.contentInset.bottom = coveredHeight
    }

    func keyboardHelper(keyboardHelper: KeyboardHelper, keyboardDidShowWithState state: KeyboardState) {
    }

    func keyboardHelper(keyboardHelper: KeyboardHelper, keyboardWillHideWithState state: KeyboardState) {
        tableView.contentInset.bottom = 0
    }
}

// MARK: - SearchInputViewDelegate
extension LoginListViewController: SearchInputViewDelegate {

    @objc func searchInputView(searchView: SearchInputView, didChangeTextTo text: String) {
        searchLoginsWithText(text)
    }

    @objc func searchInputViewBeganEditing(searchView: SearchInputView) {
        // Trigger a cancel for editing
        SELcancel()

        // Hide the edit button while we're searching
        navigationItem.rightBarButtonItem = nil
        activeLoginQuery = profile.logins.getAllLogins()
            .bindQueue(dispatch_get_main_queue(), f: reloadTableWithResult)
    }

    @objc func searchInputViewFinishedEditing(searchView: SearchInputView) {
        // Show the edit after we're done with the search
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .Edit, target: self, action: "SELedit")
        activeLoginQuery = profile.logins.getAllLogins()
            .bindQueue(dispatch_get_main_queue(), f: reloadTableWithResult)
    }

    private func searchLoginsWithText(text: String) -> Success {
        activeLoginQuery = profile.logins.searchLoginsWithQuery(text)
            .bindQueue(dispatch_get_main_queue(), f: reloadTableWithResult)
        return activeLoginQuery!
    }

    private func reloadTableWithResult(result: Maybe<Cursor<Login>>) -> Success {
        loginDataSource.cursor = result.successValue
        tableView.reloadData()
        activeLoginQuery = nil
        return succeed()
    }
}

// MARK: - LoginFaviconLoaderDelegate
extension LoginListViewController: LoginFaviconLoaderDelegate {

    private func linkFavicons(favicons: [Favicon], withLogin: Login) -> Success {
        return succeed()
    }

    func didFinishLoadingFavicons(favicons: [Favicon], forLogin login: Login) {
        // Find the row we want to update with the favicon
        guard let indexPath = loginDataSource.indexPathForLogin(login) else {
            return
        }

        linkFavicons(favicons, withLogin: login).uponQueue(dispatch_get_main_queue()) { _ in
            self.loginDataSource.loginFaviconMap[login] = favicons

            // Invalidate the cell that contains the updated login if it's visible. If not, it will get updated
            // the next call to cellForIndexPath
            if self.tableView.indexPathsForVisibleRows?.contains(indexPath) ?? false {
                // TODO: Ideally we would want to reload the single cell but for some reason the contents of the 
                // UITableViewCell get all messed up and animates everything to the left.
                self.tableView.reloadData()
            }
        }
    }
}

/// Controller that keeps track of selected indexes
private class ListSelectionController: NSObject {

    private unowned let tableView: UITableView

    private(set) var selectedIndexPaths = [NSIndexPath]()

    var selectedCount: Int {
        return selectedIndexPaths.count
    }

    init(tableView: UITableView) {
        self.tableView = tableView
        super.init()
    }

    func selectIndexPath(indexPath: NSIndexPath) {
        selectedIndexPaths.append(indexPath)
    }

    func indexPathIsSelected(indexPath: NSIndexPath) -> Bool {
        return selectedIndexPaths.contains(indexPath) { path1, path2 in
            return path1.row == path2.row && path1.section == path2.section
        }
    }

    func deselectIndexPath(indexPath: NSIndexPath) {
        guard let foundSelectedPath = (selectedIndexPaths.filter { $0.row == indexPath.row && $0.section == indexPath.section }).first,
              let indexToRemove = selectedIndexPaths.indexOf(foundSelectedPath) else {
            return
        }

        selectedIndexPaths.removeAtIndex(indexToRemove)
    }

    func deselectAll() {
        selectedIndexPaths.removeAll()
    }

    func selectIndexPaths(indexPaths: [NSIndexPath]) {
        selectedIndexPaths += indexPaths
    }
}

/// Loader containg logic for fetching favicons associated with a Login
private class LoginFaviconLoader: NSObject {

    private unowned var profile: Profile

    var delegate: LoginFaviconLoaderDelegate? = nil

    init(profile: Profile) {
        self.profile = profile
        super.init()
    }

    func loadFaviconsForLogins(logins: [Login]) {
        logins.forEach { login in
            loadFaviconsForLogin(login)?.uponQueue(dispatch_get_main_queue()) { result in
                if let favicons = result.successValue {
                    self.delegate?.didFinishLoadingFavicons(favicons, forLogin: login)
                }
            }
        }
    }

    func loadFaviconsForLogin(login: Login) -> Deferred<Maybe<[Favicon]>>? {
        guard let url = login.hostname.asURL else {
            return nil
        }
        return FaviconFetcher.getForURL(url, profile: self.profile)
    }
}

protocol LoginFaviconLoaderDelegate {
    func didFinishLoadingFavicons(favicons: [Favicon], forLogin login: Login)
}

/// Data source for handling LoginData objects from a Cursor
private class LoginCursorDataSource: NSObject, UITableViewDataSource {

    var cursor: Cursor<Login>?

    var loginFaviconMap = [Login: [Favicon]]()

    func loginAtIndexPath(indexPath: NSIndexPath) -> Login {
        return loginsForSection(indexPath.section)[indexPath.row]
    }

    func indexPathForLogin(login: Login) -> NSIndexPath? {
        guard let baseDomain = login.hostname.asURL?.baseDomain() else {
            return nil
        }

        let firstChar = baseDomain.uppercaseString[baseDomain.startIndex]

        guard let section = sectionIndexTitles()?.indexOf(String(firstChar)),
              let row = loginsForSection(section).indexOf(login) else {
            return nil
        }
        return NSIndexPath(forRow: row, inSection: section)
    }

    @objc func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return sectionIndexTitles()?.count ?? 0
    }

    @objc func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return loginsForSection(section).count
    }

    @objc func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier(LoginCellIdentifier, forIndexPath: indexPath) as! LoginTableViewCell

        let login = loginAtIndexPath(indexPath)
        cell.style = .IconAndBothLabels
        cell.updateCellWithLogin(login)

        let favicon = bestFittingFaviconForLogin(login)
        if let faviconURL = favicon?.url.asURL {
            cell.iconImageView.sd_setImageWithURL(faviconURL, placeholderImage: UIImage(named: "faviconFox"))
        }
        return cell
    }

    @objc func sectionIndexTitlesForTableView(tableView: UITableView) -> [String]? {
        return sectionIndexTitles()
    }

    @objc func tableView(tableView: UITableView, sectionForSectionIndexTitle title: String, atIndex index: Int) -> Int {
        guard let titles = sectionIndexTitles() where index < titles.count && index >= 0 else {
            return 0
        }
        return titles.indexOf(title) ?? 0
    }

    @objc func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sectionIndexTitles()?[section]
    }

    private func sectionIndexTitles() -> [String]? {
        guard cursor?.count > 0 else {
            return nil
        }

        var firstHostnameCharacters = [Character]()
        cursor?.forEach { login in
            guard let login = login, let baseDomain = login.hostname.asURL?.baseDomain() else {
                return
            }

            let firstChar = baseDomain.uppercaseString[baseDomain.startIndex]
            if !firstHostnameCharacters.contains(firstChar) {
                firstHostnameCharacters.append(firstChar)
            }
        }
        let sectionTitles = firstHostnameCharacters.map { String($0) }
        return sectionTitles.sort()
    }

    private func loginsForSection(section: Int) -> [Login] {
        guard let sectionTitles = sectionIndexTitles() else {
            return []
        }

        let titleForSectionAtIndex = sectionTitles[section]
        let logins = cursor?.filter { $0?.hostname.asURL?.baseDomain()?.uppercaseString.startsWith(titleForSectionAtIndex) ?? false }
        let flattenLogins = logins?.flatMap { $0 } ?? []
        return flattenLogins.sort { login1, login2 in
            let baseDomain1 = login1.hostname.asURL?.baseDomain()
            let baseDomain2 = login2.hostname.asURL?.baseDomain()
            let host1 = login1.hostname.asURL?.host
            let host2 = login2.hostname.asURL?.host

            if baseDomain1 == baseDomain2 {
                return host1 < host2
            } else {
                return baseDomain1 < baseDomain2
            }
        }
    }

    private func bestFittingFaviconForLogin(login: Login) -> Favicon? {
        var bestFitFavicon: Favicon?
        loginFaviconMap[login]?.forEach { favicon in
            bestFitFavicon = favicon
        }
        return bestFitFavicon
    }
}
