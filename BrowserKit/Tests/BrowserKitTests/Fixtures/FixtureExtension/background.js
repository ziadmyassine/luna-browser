chrome.storage.local.set({ ran: true }, () => {
  chrome.tabs.query({}, (tabs) => {
    chrome.tabs.create({ url: "https://example.com/?luna-fixture=" + tabs.length });
  });
});
