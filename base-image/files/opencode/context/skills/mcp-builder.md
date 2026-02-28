# Skill: MCP Server Builder

## Triggers
- Building MCP (Model Context Protocol) servers
- Integrating external APIs for LLM access
- Creating tools for AI assistants
- Python FastMCP or Node/TypeScript MCP SDK

## MCP Overview

MCP enables LLMs to interact with external services through well-designed tools. Servers expose:
- **Tools**: Actions the LLM can perform
- **Resources**: Data the LLM can read
- **Prompts**: Templates for common operations

## Python (FastMCP)

```python
from fastmcp import FastMCP

mcp = FastMCP("my-server")

@mcp.tool()
def search_database(query: str) -> list[dict]:
    """Search the database for matching records."""
    # Implementation
    return results

@mcp.resource("config://settings")
def get_settings() -> str:
    """Return current configuration."""
    return json.dumps(settings)

if __name__ == "__main__":
    mcp.run()
```

## TypeScript (MCP SDK)

```typescript
import { Server } from "@modelcontextprotocol/sdk/server";

const server = new Server({
  name: "my-server",
  version: "1.0.0"
});

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [{
    name: "search_database",
    description: "Search the database",
    inputSchema: { type: "object", properties: { query: { type: "string" }}}
  }]
}));
```

## Best Practices
- Clear, descriptive tool names
- Comprehensive input schemas
- Helpful error messages
- Proper authentication handling
- Rate limiting for external APIs
- Logging for debugging
