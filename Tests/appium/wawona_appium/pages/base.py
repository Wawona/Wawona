"""Shared Appium find / tap helpers using accessibility id = wwn.*."""

from __future__ import annotations

import time
from typing import Any

from appium.webdriver.common.appiumby import AppiumBy
from selenium.common.exceptions import (
    InvalidSessionIdException,
    NoSuchElementException,
    TimeoutException,
    WebDriverException,
)
from selenium.webdriver.remote.webdriver import WebDriver
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait


class BasePage:
    def __init__(self, driver: WebDriver, timeout: float = 20.0) -> None:
        self.driver = driver
        self.timeout = timeout

    def by_id(self, accessibility_id: str):
        return (AppiumBy.ACCESSIBILITY_ID, accessibility_id)

    def find(self, accessibility_id: str):
        return self.driver.find_element(*self.by_id(accessibility_id))

    def exists(self, accessibility_id: str) -> bool:
        try:
            self.find(accessibility_id)
            return True
        except NoSuchElementException:
            return False
        except InvalidSessionIdException:
            raise
        except WebDriverException:
            # Mac2 often maps missing AX nodes to 404 ProxyRequestError.
            return False

    def wait_visible(self, accessibility_id: str, timeout: float | None = None):
        wait = WebDriverWait(self.driver, timeout or self.timeout)
        return wait.until(EC.visibility_of_element_located(self.by_id(accessibility_id)))

    def wait_gone(self, accessibility_id: str, timeout: float | None = None) -> bool:
        end = time.time() + (timeout or self.timeout)
        while time.time() < end:
            if not self.exists(accessibility_id):
                return True
            time.sleep(0.25)
        return not self.exists(accessibility_id)

    def tap(self, accessibility_id: str, timeout: float | None = None) -> None:
        el = self.wait_visible(accessibility_id, timeout=timeout)
        el.click()

    def type_into(self, accessibility_id: str, text: str, clear: bool = True) -> None:
        el = self.wait_visible(accessibility_id)
        if clear:
            try:
                el.clear()
            except Exception:
                pass
        el.send_keys(text)

    def assert_absent(self, accessibility_id: str) -> None:
        if self.exists(accessibility_id):
            raise AssertionError(
                f"Expected {accessibility_id!r} absent (forbidden gate), but it is present"
            )

    def screenshot(self, path: str) -> None:
        self.driver.get_screenshot_as_file(path)

    def dismiss_welcome_if_present(self) -> None:
        if self.exists("wwn.welcome.continue"):
            self.tap("wwn.welcome.continue")
            time.sleep(0.5)
