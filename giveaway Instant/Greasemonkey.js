// ==UserScript==
// @name         Instant Gaming Auto Giveaway 
// @description  Automatically clicks participate buttons on Instant-Gaming giveaways.
// @version      2.1
// @author       mirage
// @namespace    https://github.com/ClementBobin/giveaway Instant/InstantGamingGiveawayList
// @match        *://www.instant-gaming.com/*/giveaway/*
// @run-at       document-idle
// @grant        GM_registerMenuCommand
// @downloadURL  https://github.com/ClementBobin/InstantGamingGiveawayList/raw/main/giveaway Instant/Greasemonkey.js
// @updateURL    https://github.com/ClementBobin/InstantGamingGiveawayList/raw/giveaway Instant/main/Greasemonkey.js
// ==/UserScript==

(function() {
  // Configuration Section
  const config = {
    minDelay: 3000, // Minimum delay before navigating to the next giveaway (in milliseconds)
    maxDelay: 10000, // Maximum delay before navigating to the next giveaway (in milliseconds)
    retryMinDelay: 1000, // Minimum delay for retrying actions (in milliseconds)
    retryMaxDelay: 2500, // Maximum delay for retrying actions (in milliseconds)
    maxRetries: 3, // Maximum number of retries for failed actions
    giveawayRepoUrl: "https://raw.githubusercontent.com/ClementBobin/InstantGamingGiveawayList/main/giveawayLinks.json", // URL to the JSON file in the GitHub repo
    discordWebhookUrl: "", // Discord webhook URL for error reporting (optional)
  };

  let giveawayLinks = [];
  let currentIndex = localStorage.getItem("currentIndex") || 0;
  let retryCount = 0;

  // Function to log messages
  function log(message, type = "info") {
    const logTypes = {
      info: "INFO",
      warn: "WARNING",
      error: "ERROR",
    };
    console.log(`[${logTypes[type]}]: ${message}`);
    if (type === "error" && config.discordWebhookUrl) {
      fetch(config.discordWebhookUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ content: `[${logTypes[type]}]: ${message}` }),
      });
    }
  }

  // Function to navigate and participate in giveaways
  function navigateAndParticipate() {
    log(`Navigating to giveaway index ${currentIndex}...`);
    if (currentIndex < giveawayLinks.length) {
      window.location.href = giveawayLinks[currentIndex] + "?igr=mirage1";
      currentIndex++;
      localStorage.setItem("currentIndex", currentIndex);
    } else {
      localStorage.setItem("currentIndex", 0);
      log("All giveaways participated!");
      window.location.href = "https://www.instant-gaming.com/fr/";
    }
  }

  // Function to fetch giveaway links from the GitHub repo
  async function fetchGiveawayLinks() {
    try {
      const response = await fetch(config.giveawayRepoUrl);
      if (!response.ok) {
        throw new Error(`Failed to fetch giveaway links: ${response.statusText}`);
      }
      giveawayLinks = await response.json();
      log(`Fetched ${giveawayLinks.length} giveaway links.`);
      // Start processing after fetching the links
      checkCurrentPage();
    } catch (error) {
      log(`Error fetching giveaway links: ${error.message}`, "error");
    }
  }

  // Function to handle errors and retries
  function handleError(error) {
    log(`Error encountered: ${error.message}`, "error");
    if (retryCount < config.maxRetries) {
      retryCount++;
      log(`Retrying action (${retryCount}/${config.maxRetries})...`, "warn");
      setTimeout(() => {
        onGiveawayPageLoad(); // Retry the action
      }, getRandomDelay(config.retryMinDelay, config.retryMaxDelay));
    } else {
      log("Max retries reached. Moving to the next giveaway.", "error");
      retryCount = 0;
      navigateAndParticipate();
    }
  }

  // Function to click social buttons without opening the links
  function socials() {
    try {
      const socialButtons = document.querySelectorAll("a.button.reward.alerts");
      if (socialButtons.length > 0) {
        log(`Clicking ${socialButtons.length} social buttons...`);
        socialButtons.forEach(button => {
          button.addEventListener('click', (e) => {
            e.preventDefault(); // Prevent the link from opening
          });
          button.click(); // Trigger the click programmatically
          log(`Clicked on social button: ${button.href}`);
        });
      } else {
        throw new Error("No social buttons found!");
      }
    } catch (error) {
      handleError(error);
    }
  }

  // Function to participate in the giveaway
  function participate() {
    try {
      const participateButton = document.querySelector("button.button.validate");
      if (participateButton) {
        log("Clicking participate button...");
        participateButton.click();
      } else {
        throw new Error("Participate button not found");
      }
    } catch (error) {
      handleError(error);
    }
  }

  // Function to handle actions on giveaway page load
  function onGiveawayPageLoad() {
    log("Executing actions on giveaway page load...");
    try {
      participate();
      socials();
      // Only navigate after all actions are complete
      setTimeout(() => {
        retryCount = 0; // Reset retry count after successful execution
        navigateAndParticipate();
      }, getRandomDelay(config.minDelay, config.maxDelay));
    } catch (error) {
      handleError(error);
    }
  }

  // Function to get a random delay within a specified range
  function getRandomDelay(min = config.minDelay, max = config.maxDelay) {
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }

  // Function to check the current page and trigger appropriate actions
  function checkCurrentPage() {
    // Check if current page is a giveaway page and trigger actions
    if (document.querySelector("span.e404")) {
      log("404 Error: Page not found, sending Discord webhook...", "error");
      setTimeout(navigateAndParticipate, getRandomDelay(config.retryMinDelay, config.retryMaxDelay));
    } else if (document.querySelector("span.giveaway-over")) {
      log("Giveaway finished, skipping...", "warn");
      setTimeout(navigateAndParticipate, getRandomDelay(config.retryMinDelay, config.retryMaxDelay));
    } else if (giveawayLinks.some(link => window.location.href.startsWith(link))) {
      log(`Detected giveaway page: ${window.location.href}`);
      onGiveawayPageLoad();
    } else if (window.location.href === "https://www.instant-gaming.com/fr/") {
      log("Already on homepage.");
    } else {
      log("Navigating to next giveaway...");
      navigateAndParticipate();
    }
  }

  // Start the script by fetching giveaway links from GitHub
  fetchGiveawayLinks();
})();
