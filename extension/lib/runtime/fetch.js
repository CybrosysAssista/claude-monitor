const { GLib, Soup } = imports.gi;

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
    for (const [name, value] of normalizeHeaders(headers)) {
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
    const session = new Soup.Session();

    async function fetch(url, options = {}) {
        const method = options.method ?? 'GET';
        const message = Soup.Message.new(method, url);

        if (!message)
            throw new Error(`Invalid URL: ${url}`);

        for (const [name, value] of normalizeHeaders(options.headers))
            message.request_headers.append(name, value);

        const body = resolveBody(options);
        if (body !== null) {
            const encoded = typeof body === 'string'
                ? new TextEncoder().encode(body)
                : body;
            message.set_request_body_from_bytes(
                getContentType(options.headers),
                GLib.Bytes.new(encoded),
            );
        }

        const bytes = await new Promise((resolve, reject) => {
            session.send_and_read_async(
                message,
                GLib.PRIORITY_DEFAULT,
                null,
                (_session, result) => {
                    try {
                        resolve(session.send_and_read_finish(result));
                    } catch (e) {
                        reject(e);
                    }
                },
            );
        });

        const status = message.status_code;
        const text = new TextDecoder().decode(bytes.get_data() ?? new Uint8Array());
        return createResponse(status, text);
    }

    function dispose() {
        session.abort();
    }

    return { fetch, dispose };
};
