'use strict';

const fs = require('fs');
const language = require('../lib/language')(fs);
const should = require('should');

describe('Mood of the day', function() {

  function makeCtx (pluginBase) {
    return {
      settings: {}
      , language: language
      , pluginBase: pluginBase
    };
  }

  var moodoftheday = require('../lib/plugins/moodoftheday')(makeCtx());

  it('has moods, each with an emoji and a caption', function(done) {
    moodoftheday.moods.length.should.be.greaterThan(0);

    moodoftheday.moods.forEach(function eachMood (mood) {
      mood.emoji.should.be.a.String().and.not.be.empty();
      mood.caption.should.be.a.String().and.not.be.empty();
    });

    done();
  });

  // ~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.

  it('returns the same mood all day', function(done) {
    var justAfterMidnight = new Date(2026, 7, 14, 0, 0, 1);
    var midMorning = new Date(2026, 7, 14, 9, 17, 43);
    var justBeforeMidnight = new Date(2026, 7, 14, 23, 59, 59);

    var mood = moodoftheday.moodForDate(midMorning);

    moodoftheday.moodForDate(justAfterMidnight).should.eql(mood);
    moodoftheday.moodForDate(justBeforeMidnight).should.eql(mood);

    done();
  });

  // ~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.

  it('always returns a mood from the list', function(done) {
    for (var i = 0; i < 2000; i++) {
      var mood = moodoftheday.moodForDate(new Date(2024, 0, 1 + i));
      moodoftheday.moods.indexOf(mood).should.be.greaterThan(-1);
    }

    done();
  });

  // ~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.

  it('spreads moods across the list rather than clustering', function(done) {
    var seen = {};

    for (var i = 0; i < 365; i++) {
      seen[moodoftheday.moodForDate(new Date(2026, 0, 1 + i)).emoji] = true;
    }

    Object.keys(seen).length.should.be.greaterThan(moodoftheday.moods.length / 2);

    done();
  });

  // ~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.

  it('sets a pill to the emoji, with the caption in the tooltip', function(done) {
    var expected = moodoftheday.moodForDate(new Date());

    var ctx = makeCtx({
      updatePillText: function mockedUpdatePillText (plugin, options) {
        plugin.name.should.equal('moodoftheday');
        options.value.should.equal(expected.emoji);
        options.info[0].value.should.equal(expected.caption);
        options.hide.should.equal(false);
        done();
      }
    });

    var sandbox = require('../lib/sandbox')();
    var sbx = sandbox.clientInit(ctx, Date.now(), {});
    var plugin = require('../lib/plugins/moodoftheday')(ctx);

    plugin.setProperties(sbx);
    plugin.updateVisualisation(sbx);
  });

  // ~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.~.

  it('does not read CGM data or raise notifications', function(done) {
    // This pill is decorative. Growing a checkNotifications() would let a joke
    // reach the alarm path, which is not something we want to discover in prod.
    should.not.exist(moodoftheday.checkNotifications);
    should.not.exist(moodoftheday.virtAsst);

    var ctx = makeCtx({
      updatePillText: function mockedUpdatePillText () {}
    });

    var sandbox = require('../lib/sandbox')();
    var sbx = sandbox.clientInit(ctx, Date.now(), {});

    // No data at all in the sandbox - the plugin must still render.
    delete sbx.data;

    var plugin = require('../lib/plugins/moodoftheday')(ctx);
    plugin.setProperties(sbx);
    plugin.updateVisualisation(sbx);

    done();
  });

});
