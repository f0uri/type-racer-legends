package com.typeracerlegends.game

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Home-screen widget: daily streak + best WPM. Data is pushed from Flutter (WidgetService). */
class TypeRacerWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.trl_widget).apply {
                val streak = widgetData.getInt("streak", 0)
                val best = widgetData.getInt("best_wpm", 0)
                setTextViewText(R.id.widget_streak, streak.toString())
                setTextViewText(R.id.widget_best, best.toString())
                setTextViewText(R.id.widget_name, widgetData.getString("name", "Type Racer Legends"))
                val pending = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                setOnClickPendingIntent(R.id.widget_root, pending)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
