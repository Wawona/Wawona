package com.aspauldingcode.wawona

import android.content.Context
import android.view.inputmethod.InputMethodManager
import java.util.Locale

/**
 * Map Android locale / IME subtype → XKB RMLVO layout+variant.
 *
 * Interim follow-system bridge for #60 / #141 until Settings picker lands.
 * Physical keys stay position→evdev; clients resolve symbols via this keymap.
 */
object KeyboardLayouts {
    data class XkbRmlvo(val layout: String, val variant: String = "")

    fun resolveSystemLayout(context: Context): XkbRmlvo {
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        val subtypeLocale = imm?.currentInputMethodSubtype?.locale?.takeIf { it.isNotBlank() }
        val locale = when {
            !subtypeLocale.isNullOrBlank() -> Locale.forLanguageTag(subtypeLocale.replace('_', '-'))
            else -> Locale.getDefault()
        }
        return fromLocale(locale)
    }

    fun fromLocale(locale: Locale): XkbRmlvo {
        val lang = locale.language.lowercase(Locale.ROOT)
        val country = locale.country.uppercase(Locale.ROOT)
        return when (lang) {
            "en" -> when (country) {
                "GB", "UK" -> XkbRmlvo("gb")
                "AU" -> XkbRmlvo("us") // close enough; us(intl) optional later
                else -> XkbRmlvo("us")
            }
            "de" -> when (country) {
                "CH" -> XkbRmlvo("ch")
                "AT" -> XkbRmlvo("de")
                else -> XkbRmlvo("de")
            }
            "fr" -> when (country) {
                "BE" -> XkbRmlvo("be")
                "CH" -> XkbRmlvo("ch", "fr")
                "CA" -> XkbRmlvo("ca")
                else -> XkbRmlvo("fr")
            }
            "es" -> when (country) {
                "MX", "LATAM" -> XkbRmlvo("latam")
                else -> XkbRmlvo("es")
            }
            "pt" -> when (country) {
                "BR" -> XkbRmlvo("br")
                else -> XkbRmlvo("pt")
            }
            "it" -> XkbRmlvo("it")
            "nl" -> XkbRmlvo("nl")
            "pl" -> XkbRmlvo("pl")
            "ru" -> XkbRmlvo("ru")
            "uk" -> XkbRmlvo("ua")
            "sv" -> XkbRmlvo("se")
            "nb", "nn", "no" -> XkbRmlvo("no")
            "da" -> XkbRmlvo("dk")
            "fi" -> XkbRmlvo("fi")
            "tr" -> XkbRmlvo("tr")
            "cs" -> XkbRmlvo("cz")
            "sk" -> XkbRmlvo("sk")
            "hu" -> XkbRmlvo("hu")
            "ro" -> XkbRmlvo("ro")
            "el" -> XkbRmlvo("gr")
            "he", "iw" -> XkbRmlvo("il")
            "ar" -> XkbRmlvo("ara")
            "ja" -> XkbRmlvo("jp")
            "ko" -> XkbRmlvo("kr")
            "zh" -> when (country) {
                "TW", "HK" -> XkbRmlvo("tw")
                else -> XkbRmlvo("cn")
            }
            "hi" -> XkbRmlvo("in")
            "th" -> XkbRmlvo("th")
            "vi" -> XkbRmlvo("vn")
            "id" -> XkbRmlvo("us") // common ID keyboards are US-labeled
            else -> XkbRmlvo("us")
        }
    }
}
