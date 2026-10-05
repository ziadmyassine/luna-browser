import Foundation

/// The part of `PasswordForms.script` that waits for a field to stop moving
/// before reporting where it is. Apart for that file's length limit; it is
/// spliced into the script's scope, where `post` is defined.
extension PasswordForms {

    static let settleScript = """
      // The picker hangs from the field, so the field is measured once it has
      // stopped moving. Microsoft's password step slides in from the side, and
      // a rect read mid-slide put the picker beside the field until the next
      // report moved it under. Frame by frame, until the field has held still
      // for three frames — a page's own script may move it only every other
      // frame — and no animation is running on it or on anything holding it;
      // a second at most. Only the newest wait reports; `gone` cancels it. A timer
      // rather than `requestAnimationFrame`, which a page not on screen never
      // calls back.
      var waiting = 0;
      var moving = function (el) {
        return !!document.getAnimations && document.getAnimations().some(function (a) {
          var target = a.effect && a.effect.target;
          return a.playState === 'running' && target && target.contains && target.contains(el);
        });
      };
      var postAt = function (el, build) {
        var mine = ++waiting, last = null, still = 0, until = Date.now() + 1000;
        var step = function () {
          if (mine !== waiting) { return; }
          var r = el.getBoundingClientRect();
          var key = [r.left, r.top, r.width, r.height].join(',');
          still = key === last ? still + 1 : 0;
          if ((still >= 3 && !moving(el)) || Date.now() > until) {
            post(build({ x: r.left, y: r.top, width: r.width, height: r.height }));
            return;
          }
          last = key;
          setTimeout(step, 16);
        };
        step();
      };
    """
}
