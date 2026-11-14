/*
 * Copyright (c) 2016 Samsung Electronics Co., Ltd.
 *      http://www.samsung.com
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#include <linux/kernel.h>
#include <linux/input.h>
#include <linux/hrtimer.h>
#include <linux/ktime.h>
#include <linux/delay.h>
#include <linux/sec_debug_hard_reset_hook.h>
#include <linux/gpio.h>
#include <linux/spinlock.h>

enum hard_reset_key {
	RESET_POWER,
	RESET_VOLUME_DOWN,
	RESET_KEY_COUNT,
};

static struct {
	int gpio;
	bool active_low;
	bool pressed;
} reset_keys[RESET_KEY_COUNT];
static DEFINE_SPINLOCK(reset_keys_lock);
static struct hrtimer hard_reset_hook_timer;
static bool hard_reset_occurred;

static enum hrtimer_restart hard_reset_hook_callback(struct hrtimer *hrtimer)
{
	unsigned long flags;
	bool confirmed = true;
	int i;

	spin_lock_irqsave(&reset_keys_lock, flags);
	for (i = 0; i < RESET_KEY_COUNT; i++) {
		int level;

		if (!reset_keys[i].pressed) {
			confirmed = false;
			break;
		}
		level = gpio_get_value(reset_keys[i].gpio);
		if (level < 0 || !!level == reset_keys[i].active_low) {
			confirmed = false;
			break;
		}
	}
	spin_unlock_irqrestore(&reset_keys_lock, flags);

	if (!confirmed) {
		pr_warn("Hard Reset cancelled: key GPIOs no longer asserted\n");
		return HRTIMER_NORESTART;
	}

	pr_err("Hard Reset\n");
	hard_reset_occurred = true;
	BUG();
	return HRTIMER_NORESTART;
}

void hard_reset_hook(unsigned int code, int gpio, bool active_low, bool pressed)
{
	unsigned long flags;
	int key;

	switch (code) {
	case KEY_POWER:
		key = RESET_POWER;
		break;
	case KEY_VOLUMEDOWN:
		key = RESET_VOLUME_DOWN;
		break;
	default:
		return;
	}
	if (!gpio_is_valid(gpio) || gpio_cansleep(gpio))
		return;

	spin_lock_irqsave(&reset_keys_lock, flags);
	reset_keys[key].gpio = gpio;
	reset_keys[key].active_low = active_low;
	reset_keys[key].pressed = pressed;
	if (reset_keys[RESET_POWER].pressed && reset_keys[RESET_VOLUME_DOWN].pressed) {
		if (!hrtimer_active(&hard_reset_hook_timer))
			hrtimer_start(&hard_reset_hook_timer, ktime_set(6, 0),
				      HRTIMER_MODE_REL);
	} else {
		hrtimer_try_to_cancel(&hard_reset_hook_timer);
	}
	spin_unlock_irqrestore(&reset_keys_lock, flags);
}

bool is_hard_reset_occurred(void)
{
	return hard_reset_occurred;
}

void hard_reset_delay(void)
{
	/* HQE team request hard reset key should guarantee 7 seconds.
	 * To get proper stack, hard reset hook starts after 6 seconds.
	 * And it will reboot before 7 seconds.
	 * Add delay to keep the 7 seconds
	 */
	if (hard_reset_occurred) {
		pr_err("wait until PMIC reset occurred");
		mdelay(2000);
	}
}

int __init hard_reset_hook_init(void)
{
	hrtimer_init(&hard_reset_hook_timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL);
	hard_reset_hook_timer.function = hard_reset_hook_callback;

	return 0;
}

early_initcall(hard_reset_hook_init);
