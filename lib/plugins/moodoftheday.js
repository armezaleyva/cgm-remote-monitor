'use strict';

/*
 * Mood of the day - a decorative status pill showing one absurd emoji per day.
 *
 * The mood is derived from the calendar date rather than drawn at random, so it
 * stays put all day and every viewer sees the same one. updateVisualisation is
 * called on every data-loaded (roughly every five minutes as readings arrive),
 * and Math.random() there would reshuffle the pill under the viewer.
 *
 * This plugin never reads CGM data and never raises a notification.
 */

var MOODS = [
  { emoji: '😎', caption: 'Feeling Floridian' }
  , { emoji: '🪠', caption: 'Plunging ahead' }
  , { emoji: '☕', caption: 'Ready to fight on the street' }
  , { emoji: '🦆', caption: 'Suspiciously calm' }
  , { emoji: '💫', caption: 'Dissociating' }
  , { emoji: '🛸', caption: 'Not from around here' }
  , { emoji: '🍞', caption: 'Toasty' }
  , { emoji: '🪄', caption: 'Walking Houdini' }
  , { emoji: '🦥', caption: 'Low-energy & low-dopamine' }
  , { emoji: '🪥', caption: 'Doing the bare minimum, thoroughly' }
  , { emoji: '🪞', caption: 'Reflective' }
  , { emoji: '🪁', caption: 'Attached to something distant' }
  , { emoji: '🧲', caption: 'Attracting the wrong things' }
  , { emoji: '🛁', caption: 'Marinating' }
  , { emoji: '🦉', caption: 'Awake at the wrong hours' }
  , { emoji: '🦎', caption: 'Lizard' }
  , { emoji: '☀️', caption: 'Seeking skin cancer' }
  , { emoji: '🥚', caption: 'Being a good egg for once' }
  , { emoji: '😴', caption: 'Eepy' }
  , { emoji: '🧀', caption: 'Eating cheese' }
  , { emoji: '🌻', caption: 'In need of flower' }
  , { emoji: '📖', caption: 'Doing it for the plot' }
  , { emoji: '🇭🇺', caption: 'Imagine speaking two languages' }
];

function init (ctx) {
  var translate = ctx.language.translate;

  var moodoftheday = {
    name: 'moodoftheday'
    , label: 'Mood of the day'
    , pluginType: 'pill-status'
  };

  moodoftheday.moods = MOODS;

  // Local calendar date as YYYY-MM-DD, so the mood turns over at the viewer's
  // own midnight rather than UTC's.
  function dateKey (date) {
    var month = date.getMonth() + 1;
    var day = date.getDate();
    return date.getFullYear()
      + '-' + (month < 10 ? '0' : '') + month
      + '-' + (day < 10 ? '0' : '') + day;
  }

  // FNV-1a, 32-bit. Math.imul keeps the multiply from losing precision above 2^53.
  function hash (text) {
    var h = 0x811c9dc5;
    for (var i = 0; i < text.length; i++) {
      h ^= text.charCodeAt(i);
      h = Math.imul(h, 0x01000193) >>> 0;
    }
    return h >>> 0;
  }

  moodoftheday.moodForDate = function moodForDate (date) {
    /* eslint-disable-next-line security/detect-object-injection */ // index is a hash modulo the list length
    return MOODS[hash(dateKey(date)) % MOODS.length];
  };

  moodoftheday.setProperties = function setProperties (sbx) {
    sbx.offerProperty('moodoftheday', function setMood () {
      // Deliberately not sbx.time - that follows the chart brush, and the pill
      // should not change while the viewer scrubs through history.
      return moodoftheday.moodForDate(new Date());
    });
  };

  moodoftheday.updateVisualisation = function updateVisualisation (sbx) {
    var prop = sbx.properties.moodoftheday;

    sbx.pluginBase.updatePillText(moodoftheday, {
      label: translate('Mood')
      , value: prop && prop.emoji
      , info: prop ? [{ label: translate('Today'), value: prop.caption }] : null
      , hide: !prop
    });
  };

  return moodoftheday;
}

module.exports = init;
