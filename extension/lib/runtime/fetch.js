imports.gi.versions.Soup = '2.4';
const { GLib } = imports.gi;
const { Soup } = imports.gi;

function normalizeHeaders(headers) {
    if (!headers || typeof headers !== 'object')
        return [];

    return Object.entries(headers).map(([name, value]) => [name, String(value)]);
}

function resolveBody(options) {
    const body = options?.body;
    if (body === undefined || body === null)
        return null;

    if (typeof body === 'string')
        return body;

    if (body instanceof URLSearchParams)
        return body.toString();

    if (body instanceof Uint8Array)
        return body;

    return String(body);
}

function getContentType(headers) {
    const normalized = normalizeHeaders(headers);

    for (const [name, value] of normalized) {
        if (name.toLowerCase() === 'content-type')
            return value;
    }

    return 'application/octet-stream';
}

function createResponse(status, textData) {
    return {
        ok: status >= 200 && status < 300,
        status,
        async text() {
            return textData;
        },
        async json() {
            return JSON.parse(textData);
        },
    };
}

var createFetch = function() {
    const session = new Soup.SessionAsync();
    
    // Automatically handle gzip decoding
    try {
        session.add_feature_by_type(Soup.ContentDecoder.$gtype);
    } catch(e) {}

    function sendMessage(message) {
        return new Promise((resolve, reject) => {
            session.queue_message(message, (sess, msg) => {
                if (msg.status_code <= 6) {
                    reject(new Error(`Network error (Soup internal status): ${msg.status_code}`));
                    return;
                }
                
                let data = "";
                if (msg.response_body && msg.response_body.data) {
                    // Ensure data is treated as a string for JSON.parse
                    data = msg.response_body.data;
                    if (data instanceof Uint8Array || (typeof data !== 'string' && data !== null)) {
                        try {
                            data = new TextDecoder().decode(data);
                        } catch (e) {
                            data = String(data);
                        }
                    }
                }
                
                resolve({
                    status: msg.status_code,
                    data: data
                });
            });
        });
    }

    async function fetch(url, options = {}) {
        const method = options.method ?? 'GET';
        const message = Soup.Message.new(method, url);

        if (!message)
            throw new Error(`Invalid URL: ${url}`);

        for (const [name, value] of normalizeHeaders(options.headers))
            message.request_headers.append(name, value);

        const body = resolveBody(options);
        if (body !== null) {
            // Soup 2.4 way to set body
            message.set_request(getContentType(options.headers), Soup.MemoryUse.COPY, body);
        }

        const result = await sendMessage(message);
        return createResponse(result.status, result.data);
    }

    function dispose() {
        session.abort();
    }

    return {fetch, dispose};
}
