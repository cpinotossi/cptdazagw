const { app } = require('@azure/functions');

app.http('httptrigger', {
    methods: ['GET'],
    authLevel: 'anonymous',
    handler: async (request, context) => {
        try {
            // Start timing the request processing
            const requestStartTime = Date.now();
            const requestStartTimestamp = new Date(requestStartTime).toISOString();
            
            context.log(`Http function processed request for url "${request.url}"`);

            // Parse the URL to check if it contains /download path
            const url = new URL(request.url);
            const pathname = url.pathname;
            
            // Add debugging logs
            context.log(`Full URL: ${request.url}`);
            context.log(`Pathname: ${pathname}`);

            // Original functionality for non-download requests
            // Get specific commonly used properties
            const requestDetails = {
                // Headers (converted to object for easy viewing)
                headers: Object.fromEntries(request.headers.entries()),
                // Query parameters
                query: Object.fromEntries(request.query.entries()),
            };
            // Get the name parameter
            const name = request.query.get('name') || 'world';
            
            // Get the delay parameter (in seconds)
            const delayParam = request.query.get('d');
            const delaySeconds = delayParam ? parseInt(delayParam, 10) : 0;
            
            // Apply delay if specified
            if (delaySeconds > 0) {
                context.log(`Applying delay of ${delaySeconds} seconds`);
                await new Promise(resolve => setTimeout(resolve, delaySeconds * 1000));
            }

            // Prepare dynamic message based on delay
            let message = `Hello, ${name}! Here's everything about your request:`;
            if (delaySeconds > 0) {
                message = `Hello, ${name}! I waited ${delaySeconds} second${delaySeconds !== 1 ? 's' : ''} as requested. Here's everything about your request:`;
            }

            // Calculate processing time
            const requestEndTime = Date.now();
            const requestEndTimestamp = new Date().toISOString();
            const processingTimeMs = requestEndTime - requestStartTime;
            const processingTimeSeconds = (processingTimeMs / 1000).toFixed(3);

            // Prepare comprehensive response
            const response = {
                message: message,
            timing: {
                requestStartTime: requestStartTimestamp,
                requestEndTime: requestEndTimestamp,
                processingTimeMs: processingTimeMs,
                processingTimeSeconds: parseFloat(processingTimeSeconds),
                delayAppliedSeconds: delaySeconds
            },
            requestDetails: requestDetails,
        };

        context.log(`Request inspection completed for: ${name}`);
        context.log(`Total processing time: ${processingTimeMs}ms (${processingTimeSeconds}s) - Delay applied: ${delaySeconds}s`);

        return { 
            status: 200,
            headers: {
                'Content-Type': 'application/json',
                'X-Processing-Time-Ms': processingTimeMs.toString(),
                'X-Processing-Time-Seconds': processingTimeSeconds
            },
            body: JSON.stringify(response, null, 2)
        };

        } catch (error) {
            context.log.error('Error in function:', error);
            return {
                status: 500,
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    error: 'Internal server error',
                    details: error.message
                })
            };
        }
    }
});

