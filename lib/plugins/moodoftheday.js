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
  { emoji: '🦞', caption: 'Thermidorian and unbothered' }
  , { emoji: '🪠', caption: 'Plunging ahead' }
  , { emoji: '🫠', caption: 'Structurally compromised' }
  , { emoji: '🧿', caption: 'Warding off something vague' }
  , { emoji: '🦆', caption: 'Suspiciously calm' }
  , { emoji: '🗿', caption: 'No notes' }
  , { emoji: '🪤', caption: 'Bait unclear' }
  , { emoji: '🛎️', caption: 'Awaiting service' }
  , { emoji: '🧦', caption: 'One of two' }
  , { emoji: '🥌', caption: 'Sliding gracefully toward an outcome' }
  , { emoji: '🪗', caption: 'Expanding and contracting on schedule' }
  , { emoji: '🦭', caption: 'Aggressively aquatic' }
  , { emoji: '🧻', caption: 'Down to the last few' }
  , { emoji: '🪑', caption: 'Simply a chair' }
  , { emoji: '🛸', caption: 'Not from around here' }
  , { emoji: '🧊', caption: 'Emotionally refrigerated' }
  , { emoji: '🦩', caption: 'Standing on one leg for no reason' }
  , { emoji: '🪺', caption: 'Nesting, allegedly' }
  , { emoji: '🧄', caption: 'Pungent but principled' }
  , { emoji: '🎺', caption: 'Unnecessarily loud' }
  , { emoji: '🦥', caption: 'Ahead of schedule, somehow' }
  , { emoji: '🪥', caption: 'Doing the bare minimum, thoroughly' }
  , { emoji: '🛒', caption: 'Rolling with one bad wheel' }
  , { emoji: '🦔', caption: 'Prickly but well-meaning' }
  , { emoji: '🪞', caption: 'Reflective' }
  , { emoji: '🧅', caption: 'Layered' }
  , { emoji: '🦑', caption: 'Ninety percent arms' }
  , { emoji: '🪁', caption: 'Attached to something distant' }
  , { emoji: '🧲', caption: 'Attracting the wrong things' }
  , { emoji: '🦡', caption: 'Genuinely does not care' }
  , { emoji: '🪆', caption: 'There is more of this inside' }
  , { emoji: '🛁', caption: 'Marinating' }
  , { emoji: '🦉', caption: 'Awake at the wrong hours' }
  , { emoji: '🧹', caption: 'Sweeping it under something' }
  , { emoji: '🪸', caption: 'Slowly becoming a reef' }
  , { emoji: '🦦', caption: 'Floating on my back, holding hands with no one' }
  , { emoji: '🎳', caption: 'Knocked over, resetting' }
  , { emoji: '🧩', caption: 'Missing a piece, functional anyway' }
  , { emoji: '🦨', caption: 'Making my presence known' }
  , { emoji: '🪴', caption: 'Growing, slowly, in a container' }
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
