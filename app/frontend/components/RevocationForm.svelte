<script>
  let token = '';
  let xoxd = '';
  let xoxc = '';
  let detectedTypes = [];

  const tokenTypesData = JSON.parse(document.getElementById('token-types').textContent);
  const tokenTypes = tokenTypesData.map(type => ({
    name: type.name,
    regex: new RegExp(type.regex),
    hint: type.hint
  }));

  function detectTokenType(value) {
    if (!value.trim()) {
      detectedTypes = [];
      return;
    }
    detectedTypes = tokenTypes.filter(type => type.regex.test(value));
  }

  function formatDetected(types) {
    if (types.length === 1) return types[0].name;
    const last = types[types.length - 1].name;
    const rest = types.slice(0, -1).map(t => t.name).join(', ');
    return `${rest}, or ${last}`;
  }

  function getArticle(types) {
    const first = formatDetected(types)[0].toLowerCase();
    return /[aeiou]/.test(first) ? 'an' : 'a';
  }

  function handleTokenInput(e) {
    token = e.target.value;
    detectTokenType(token);
  }

  function handleXoxdInput(e) {
    xoxd = e.target.value;
  }

  function handleXoxcInput(e) {
    xoxc = e.target.value;
  }

  function isXoxcDetected(types) {
    return types.some(type => type.name === "scraped Slack client token");
  }

  function isXoxdDetected(types) {
     return types.some(type => type.name === "scraped Slack dashboard token");
   }

  function isFormValid(types) {
    if (!types.length) return false;
    
    const hasXoxc = isXoxcDetected(types);
    const hasXoxd = isXoxdDetected(types);
    
    if (hasXoxc && !xoxd.trim()) return false;
    if (hasXoxd && !xoxc.trim()) return false;
    
    return true;
  }
</script>

<form class="revocation-form" method="POST" action="/revocations">
  <input type="hidden" name="authenticity_token" value={document.querySelector('meta[name="csrf-token"]')?.content || ''} />
  
  <div class="form-group">
    <label for="token">Token</label>
    <input
      id="token"
      type="text"
      name="token"
      value={token}
      on:input={handleTokenInput}
      placeholder="Paste your token here"
      required
    />
    {#if detectedTypes.length}
      <div class="token-type-detected">
        That looks like {getArticle(detectedTypes)} <strong>{formatDetected(detectedTypes)}</strong>?
      </div>
    {/if}
  </div>

  {#if isXoxcDetected(detectedTypes)}
    <div class="form-group">
      <label for="xoxd">xoxd cookie (required for xoxc revocation)</label>
      <input
        id="xoxd"
        type="text"
        name="xoxd"
        value={xoxd}
        on:input={handleXoxdInput}
        placeholder="xoxd-... (required)"
        required
      />
      <div class="hint-text">
        xoxc tokens require the matching xoxd cookie to revoke. Please provide both.
      </div>
    </div>
  {/if}

  {#if isXoxdDetected(detectedTypes)}
    <div class="form-group">
      <label for="xoxc">xoxc token (required for xoxd revocation)</label>
      <input
        id="xoxc"
        type="text"
        name="xoxc"
        value={xoxc}
        on:input={handleXoxcInput}
        placeholder="xoxc-... (required)"
        required
      />
      <div class="hint-text">
        xoxd cookies cannot be revoked alone. Please provide the matching xoxc token to revoke both.
      </div>
    </div>
  {/if}

  {#if detectedTypes.length}
     <button type="submit" disabled={!isFormValid(detectedTypes)}>
       say goodbye, token...
     </button>
   {/if}
</form>
