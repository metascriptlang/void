package dev.metascript.voidapp;

import android.app.Activity;
import android.content.Context;
import android.os.Build;
import android.text.InputType;
import android.view.Choreographer;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputMethodManager;
import android.widget.FrameLayout;

// The root view of a voidRun app on Android: the surface bridgeAndroidApp.c renders into, and the
// touches, keys, IME text and insets it turns into sokol_app events. Every call runs on the main thread.
public final class VoidAppView extends SurfaceView implements SurfaceHolder.Callback, Choreographer.FrameCallback {
	static final int TOUCH_BEGAN = 0, TOUCH_MOVED = 1, TOUCH_ENDED = 2, TOUCH_CANCELLED = 3;

	private boolean surfaceReady;
	private boolean running = true;
	private boolean framePosted;
	private boolean textInput;
	private String composing = "";

	native void nativeSurface(Object surface, int width, int height);
	native void nativeSurfaceGone();
	native void nativeFrame();
	native void nativeTouch(int phase, long[] ids, float[] xs, float[] ys, int changed);
	native boolean nativeKey(boolean down, int keyCode, int metaState, int repeat, int unicode);
	native void nativeCommit(String text);
	native void nativePreedit(String text, int cursor);
	native void nativeInsets(int top, int left, int bottom, int right, int keyboard);
	native void nativeFocus(boolean focused);

	public VoidAppView(Context context) {
		super(context);
		getHolder().addCallback(this);
		setFocusable(true);
		setFocusableInTouchMode(true);
		setOnApplyWindowInsetsListener((view, insets) -> {
			reportInsets(insets);
			return insets;
		});
	}

	public void attach(FrameLayout root) {
		Context context = getContext();
		if (context instanceof Activity) {
			Activity activity = (Activity) context;
			activity.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
			if (Build.VERSION.SDK_INT >= 30) activity.getWindow().setDecorFitsSystemWindows(false);
		}
		root.addView(this, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
		requestFocus();
	}

	public void detach() {
		running = false;
		ViewGroup parent = (ViewGroup) getParent();
		if (parent != null) parent.removeView(this);
	}

	public void setRunning(boolean on) {
		running = on;
		postFrame();
	}

	public void setTextInput(boolean on) {
		if (textInput == on) return;
		textInput = on;
		InputMethodManager imm = (InputMethodManager) getContext().getSystemService(Context.INPUT_METHOD_SERVICE);
		if (!on) finishComposing();
		imm.restartInput(this);
		if (on) {
			requestFocus();
			imm.showSoftInput(this, 0);
		} else {
			imm.hideSoftInputFromWindow(getWindowToken(), 0);
		}
	}

	private void reportInsets(WindowInsets insets) {
		int top, left, bottom, right, keyboard = 0;
		if (Build.VERSION.SDK_INT >= 30) {
			android.graphics.Insets bars = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
			top = bars.top;
			left = bars.left;
			bottom = bars.bottom;
			right = bars.right;
			keyboard = insets.getInsets(WindowInsets.Type.ime()).bottom;
		} else {
			top = insets.getSystemWindowInsetTop();
			left = insets.getSystemWindowInsetLeft();
			bottom = insets.getSystemWindowInsetBottom();
			right = insets.getSystemWindowInsetRight();
		}
		nativeInsets(top, left, bottom, right, keyboard);
	}

	private void postFrame() {
		if (!running || !surfaceReady || framePosted) return;
		framePosted = true;
		Choreographer.getInstance().postFrameCallback(this);
	}

	@Override
	public void doFrame(long frameTimeNanos) {
		framePosted = false;
		if (!running || !surfaceReady) return;
		nativeFrame();
		postFrame();
	}

	@Override
	public void surfaceCreated(SurfaceHolder holder) {}

	@Override
	public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
		nativeSurface(holder.getSurface(), width, height);
		surfaceReady = true;
		postFrame();
	}

	@Override
	public void surfaceDestroyed(SurfaceHolder holder) {
		surfaceReady = false;
		nativeSurfaceGone();
	}

	@Override
	public void onWindowFocusChanged(boolean focused) {
		super.onWindowFocusChanged(focused);
		nativeFocus(focused);
	}

	@Override
	public boolean onTouchEvent(MotionEvent e) {
		int phase;
		int changed = -1;
		switch (e.getActionMasked()) {
			case MotionEvent.ACTION_DOWN:
			case MotionEvent.ACTION_POINTER_DOWN:
				phase = TOUCH_BEGAN;
				changed = e.getActionIndex();
				break;
			case MotionEvent.ACTION_MOVE:
				phase = TOUCH_MOVED;
				break;
			case MotionEvent.ACTION_UP:
			case MotionEvent.ACTION_POINTER_UP:
				phase = TOUCH_ENDED;
				changed = e.getActionIndex();
				break;
			case MotionEvent.ACTION_CANCEL:
				phase = TOUCH_CANCELLED;
				break;
			default:
				return false;
		}
		final int n = e.getPointerCount();
		long[] ids = new long[n];
		float[] xs = new float[n];
		float[] ys = new float[n];
		for (int i = 0; i < n; i++) {
			ids[i] = e.getPointerId(i);
			xs[i] = e.getX(i);
			ys[i] = e.getY(i);
		}
		nativeTouch(phase, ids, xs, ys, changed);
		return true;
	}

	private boolean key(KeyEvent e) {
		final int action = e.getAction();
		if (action == KeyEvent.ACTION_MULTIPLE && e.getKeyCode() == KeyEvent.KEYCODE_UNKNOWN) {
			nativeCommit(e.getCharacters());
			return true;
		}
		if (action != KeyEvent.ACTION_DOWN && action != KeyEvent.ACTION_UP) return false;
		final int meta = e.getMetaState();
		final int unicode = e.getUnicodeChar(meta & ~(KeyEvent.META_CTRL_MASK | KeyEvent.META_META_MASK));
		return nativeKey(action == KeyEvent.ACTION_DOWN, e.getKeyCode(), meta, e.getRepeatCount(), unicode);
	}

	@Override
	public boolean onKeyDown(int keyCode, KeyEvent e) { return key(e) || super.onKeyDown(keyCode, e); }

	@Override
	public boolean onKeyUp(int keyCode, KeyEvent e) { return key(e) || super.onKeyUp(keyCode, e); }

	@Override
	public boolean onKeyMultiple(int keyCode, int count, KeyEvent e) { return key(e) || super.onKeyMultiple(keyCode, count, e); }

	@Override
	public boolean onCheckIsTextEditor() { return textInput; }

	private void finishComposing() {
		if (composing.isEmpty()) return;
		final String text = composing;
		composing = "";
		nativePreedit("", 0);
		nativeCommit(text);
	}

	@Override
	public InputConnection onCreateInputConnection(EditorInfo info) {
		if (!textInput) return null;
		info.inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE;
		info.imeOptions = EditorInfo.IME_FLAG_NO_FULLSCREEN | EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_ACTION_NONE;
		return new BaseInputConnection(this, false) {
			@Override
			public boolean commitText(CharSequence text, int newCursorPosition) {
				if (!composing.isEmpty()) {
					composing = "";
					nativePreedit("", 0);
				}
				nativeCommit(text.toString());
				return true;
			}

			@Override
			public boolean setComposingText(CharSequence text, int newCursorPosition) {
				composing = text.toString();
				nativePreedit(composing, composing.length());
				return true;
			}

			@Override
			public boolean finishComposingText() {
				finishComposing();
				return true;
			}

			@Override
			public boolean deleteSurroundingText(int beforeLength, int afterLength) {
				for (int i = 0; i < beforeLength; i++) {
					key(new KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL));
					key(new KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL));
				}
				return true;
			}

			@Override
			public boolean sendKeyEvent(KeyEvent e) { return key(e); }
		};
	}
}
