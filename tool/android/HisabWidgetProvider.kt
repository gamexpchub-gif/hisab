package __PACKAGE__

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

// Hisab AI home-screen widget: today's sale, cash in hand and money to collect.
// The numbers are written by the app (home_widget) whenever the books change.
class HisabWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.hisab_widget).apply {
                setTextViewText(R.id.w_shop, widgetData.getString("shop", "Hisab AI"))
                setTextViewText(R.id.w_sale, widgetData.getString("sale", "₹0"))
                setTextViewText(R.id.w_bills, widgetData.getString("bills", "0 bills"))
                setTextViewText(R.id.w_cash, widgetData.getString("cash", "₹0"))
                setTextViewText(R.id.w_due, widgetData.getString("due", "₹0"))
                setTextViewText(R.id.w_updated, widgetData.getString("updated", "Open the app to update"))
                setOnClickPendingIntent(R.id.w_root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
