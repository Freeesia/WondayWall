package com.studiofreesia.wondaywall.ui.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.studiofreesia.wondaywall.services.AppConfigService
import com.studiofreesia.wondaywall.services.ContextService
import com.studiofreesia.wondaywall.services.GenerationCoordinator
import com.studiofreesia.wondaywall.services.GoogleAiServiceProtocol
import com.studiofreesia.wondaywall.services.HistoryService
import com.studiofreesia.wondaywall.services.TaskSchedulerService
import com.studiofreesia.wondaywall.services.WallpaperService
import com.studiofreesia.wondaywall.ui.screens.data.DataScreen
import com.studiofreesia.wondaywall.ui.screens.data.DataViewModel
import com.studiofreesia.wondaywall.ui.screens.history.HistoryDetailScreen
import com.studiofreesia.wondaywall.ui.screens.history.HistoryScreen
import com.studiofreesia.wondaywall.ui.screens.history.HistoryViewModel
import com.studiofreesia.wondaywall.ui.screens.home.HomeScreen
import com.studiofreesia.wondaywall.ui.screens.home.HomeViewModel
import com.studiofreesia.wondaywall.ui.screens.about.AboutScreen
import com.studiofreesia.wondaywall.ui.screens.settings.SettingsScreen
import com.studiofreesia.wondaywall.ui.screens.settings.SettingsViewModel
import com.studiofreesia.wondaywall.ui.screens.wizard.WizardScreen
import com.studiofreesia.wondaywall.ui.screens.wizard.WizardViewModel

// ナビゲーションルート定数
private object Routes {
    const val LOADING = "loading"
    const val WIZARD = "wizard"
    const val MAIN = "main"
    const val HOME = "home"
    const val DATA = "data"
    const val HISTORY = "history"
    const val HISTORY_DETAIL = "history_detail"
    const val SETTINGS = "settings"
}

// ボトムナビゲーションの項目定義
private data class BottomNavItem(
    val route: String,
    val label: String,
    val icon: androidx.compose.ui.graphics.vector.ImageVector,
)

// アプリ全体のナビゲーション
@Composable
fun AppNavigation(
    appConfigService: AppConfigService,
    generationCoordinator: GenerationCoordinator,
    historyService: HistoryService,
    wallpaperService: WallpaperService,
    contextService: ContextService,
    taskSchedulerService: TaskSchedulerService,
    googleAiService: GoogleAiServiceProtocol,
) {
    val rootNavController = rememberNavController()

    // セットアップ完了状態をAPIキーの存在で判定する
    var startDestination by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        val apiKey = appConfigService.getGoogleAiApiKey()
        startDestination = if (apiKey.isNotEmpty()) Routes.MAIN else Routes.WIZARD
    }

    if (startDestination == null) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        return
    }

    NavHost(
        navController = rootNavController,
        startDestination = startDestination!!,
    ) {
        // セットアップウィザード
        composable(Routes.WIZARD) {
            val vm: WizardViewModel = viewModel(
                factory = WizardViewModel.factory(
                    appConfigService = appConfigService,
                    contextService = contextService,
                    taskSchedulerService = taskSchedulerService,
                )
            )
            WizardScreen(
                viewModel = vm,
                onComplete = {
                    rootNavController.navigate(Routes.MAIN) {
                        popUpTo(Routes.WIZARD) { inclusive = true }
                    }
                },
            )
        }

        // メイン画面（ボトムナビゲーション付き）
        composable(Routes.MAIN) {
            MainScreen(
                appConfigService = appConfigService,
                generationCoordinator = generationCoordinator,
                historyService = historyService,
                wallpaperService = wallpaperService,
                contextService = contextService,
                taskSchedulerService = taskSchedulerService,
                googleAiService = googleAiService,
            )
        }
    }
}

// ボトムナビゲーション付きメイン画面
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MainScreen(
    appConfigService: AppConfigService,
    generationCoordinator: GenerationCoordinator,
    historyService: HistoryService,
    wallpaperService: WallpaperService,
    contextService: ContextService,
    taskSchedulerService: TaskSchedulerService,
    googleAiService: GoogleAiServiceProtocol,
) {
    val navController = rememberNavController()
    var showAboutSheet by remember { mutableStateOf(false) }
    val aboutSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    val bottomNavItems = listOf(
        BottomNavItem(Routes.HOME, "ホーム", Icons.Default.Home),
        BottomNavItem(Routes.DATA, "データ", Icons.Default.Newspaper),
        BottomNavItem(Routes.HISTORY, "履歴", Icons.Default.History),
        BottomNavItem(Routes.SETTINGS, "設定", Icons.Default.Settings),
    )

    Scaffold(
        bottomBar = {
            NavigationBar {
                val navBackStackEntry by navController.currentBackStackEntryAsState()
                val currentDestination = navBackStackEntry?.destination
                bottomNavItems.forEach { item ->
                    NavigationBarItem(
                        icon = { Icon(item.icon, contentDescription = item.label) },
                        label = { Text(item.label) },
                        selected = currentDestination?.hierarchy?.any { it.route == item.route } == true,
                        onClick = {
                            navController.navigate(item.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                    )
                }
            }
        },
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = Routes.HOME,
            // ボトムナビゲーション分のみパディングを適用する（上部はedge-to-edgeのためStatusBarはシステムが制御する）
            modifier = Modifier.padding(bottom = innerPadding.calculateBottomPadding()),
        ) {
            composable(Routes.HOME) {
                val vm: HomeViewModel = viewModel(
                    factory = HomeViewModel.factory(
                        appConfigService = appConfigService,
                        generationCoordinator = generationCoordinator,
                        historyService = historyService,
                        wallpaperService = wallpaperService,
                        taskSchedulerService = taskSchedulerService,
                        contextService = contextService,
                    )
                )
                HomeScreen(viewModel = vm)
            }
            composable(Routes.DATA) {
                val vm: DataViewModel = viewModel(
                    factory = DataViewModel.factory(
                        appConfigService = appConfigService,
                        contextService = contextService,
                    )
                )
                DataScreen(viewModel = vm)
            }
            composable(Routes.HISTORY) {
                val vm: HistoryViewModel = viewModel(
                    factory = HistoryViewModel.factory(
                        historyService = historyService,
                        wallpaperService = wallpaperService,
                        generationCoordinator = generationCoordinator,
                        appConfigService = appConfigService,
                    )
                )
                HistoryScreen(
                    viewModel = vm,
                    onNavigateToDetail = { itemId ->
                        navController.navigate("${Routes.HISTORY_DETAIL}/$itemId")
                    },
                )
            }
            composable(
                route = "${Routes.HISTORY_DETAIL}/{itemId}",
                arguments = listOf(androidx.navigation.navArgument("itemId") { type = androidx.navigation.NavType.StringType }),
            ) { backStackEntry ->
                val itemId = backStackEntry.arguments?.getString("itemId") ?: return@composable
                // historyService から非同期でアイテムを取得する
                var item by remember { mutableStateOf<com.studiofreesia.wondaywall.models.HistoryItem?>(null) }
                LaunchedEffect(itemId) {
                    item = historyService.loadHistory().firstOrNull { it.id == itemId }
                }
                item?.let {
                    HistoryDetailScreen(
                        item = it,
                        onBack = { navController.popBackStack() },
                    )
                }
            }
            composable(Routes.SETTINGS) {
                val vm: SettingsViewModel = viewModel(
                    factory = SettingsViewModel.factory(
                        appConfigService = appConfigService,
                        taskSchedulerService = taskSchedulerService,
                    )
                )
                SettingsScreen(
                    viewModel = vm,
                    onNavigateToAbout = { showAboutSheet = true },
                )
            }
        }
    }

    if (showAboutSheet) {
        ModalBottomSheet(
            onDismissRequest = { showAboutSheet = false },
            sheetState = aboutSheetState,
            dragHandle = { BottomSheetDefaults.DragHandle() },
        ) {
            AboutScreen(
                appConfigService = appConfigService,
                generationCoordinator = generationCoordinator,
                googleAiService = googleAiService,
                taskSchedulerService = taskSchedulerService,
                onClose = { showAboutSheet = false },
            )
        }
    }
}
