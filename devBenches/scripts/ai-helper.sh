#!/bin/bash

# =============================================================================
# ai-helper.sh - Enhanced AI Integration for launchDevBench
# =============================================================================
# Provides robust OpenAI API integration with proper error handling and JSON parsing
# =============================================================================

# Check if jq is available for JSON parsing
has_jq() {
    command -v jq >/dev/null 2>&1
}

# Simple JSON parser fallback when jq is not available
parse_json_content() {
    local json_response="$1"
    
    if has_jq; then
        echo "$json_response" | jq -r '.choices[0].message.content' 2>/dev/null
    else
        # Fallback parsing without jq
        echo "$json_response" | sed -n 's/.*"content"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | sed 's/\\n/\n/g'
    fi
}

# Make OpenAI API call
call_openai_api() {
    local prompt="$1"
    local max_tokens="${2:-300}"
    local temperature="${3:-0.3}"
    
    if [ -z "$OPENAI_API_KEY" ]; then
        return 1
    fi
    
    # Escape prompt for JSON
    local escaped_prompt=$(printf '%s' "$prompt" | sed 's/"/\\"/g' | sed 's/$/\\n/' | tr -d '\n')
    
    local response=$(curl -s -w "\n%{http_code}" -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "{
            \"model\": \"gpt-3.5-turbo\",
            \"messages\": [{\"role\": \"user\", \"content\": \"$escaped_prompt\"}],
            \"max_tokens\": $max_tokens,
            \"temperature\": $temperature
        }" 2>/dev/null)
    
    # Split response and HTTP code
    local http_code=$(echo "$response" | tail -n1)
    local json_response=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "200" ]; then
        parse_json_content "$json_response"
        return 0
    else
        return 1
    fi
}

# Enhanced bench recommendation with structured output
recommend_bench_ai() {
    local request="$1"
    local context="$2"
    local available_benches="$3"
    
    local prompt="You are a development environment assistant. Analyze this request and recommend the best development bench.

REQUEST: $request

CONTEXT:
$context

AVAILABLE BENCHES:
$available_benches

Please respond in this EXACT format (no extra text):
BENCH: [bench_name]
CONFIDENCE: [high/medium/low]
REASON: [brief explanation in one sentence]
ADDITIONAL: [optional suggestions or empty]"

    local ai_response=$(call_openai_api "$prompt" 250 0.2)
    
    if [ $? -eq 0 ] && [ -n "$ai_response" ]; then
        echo "$ai_response"
        return 0
    else
        return 1
    fi
}

# Parse AI response to extract bench recommendation
parse_bench_recommendation() {
    local ai_response="$1"
    
    # Extract bench name
    local bench_name=$(echo "$ai_response" | grep "^BENCH:" | sed 's/BENCH: *//' | tr '[:upper:]' '[:lower:]')
    local confidence=$(echo "$ai_response" | grep "^CONFIDENCE:" | sed 's/CONFIDENCE: *//')
    local reason=$(echo "$ai_response" | grep "^REASON:" | sed 's/REASON: *//')
    local additional=$(echo "$ai_response" | grep "^ADDITIONAL:" | sed 's/ADDITIONAL: *//')
    
    # Return structured result
    echo "BENCH_NAME=$bench_name"
    echo "CONFIDENCE=$confidence"
    echo "REASON=$reason"
    echo "ADDITIONAL=$additional"
}

# Analyze project and environment with AI
analyze_environment_ai() {
    local current_dir="$1"
    local basic_analysis="$2"
    
    local prompt="Analyze this development environment and provide recommendations:

CURRENT DIRECTORY: $current_dir
BASIC ANALYSIS:
$basic_analysis

Please provide a comprehensive analysis including:
1. Project type and technology stack
2. Development phase (new project, active development, maintenance)
3. Likely development tasks based on recent changes
4. Recommended development environment features
5. Potential issues or optimizations

Keep response concise but informative."

    call_openai_api "$prompt" 400 0.3
}

# Main function to handle AI operations
main() {
    case "$1" in
        --recommend)
            shift
            local request="$1"
            local context="$2"
            local benches="$3"
            recommend_bench_ai "$request" "$context" "$benches"
            ;;
        --parse-recommendation)
            shift
            local response="$1"
            parse_bench_recommendation "$response"
            ;;
        --analyze)
            shift
            local current_dir="$1"
            local basic_analysis="$2"
            analyze_environment_ai "$current_dir" "$basic_analysis"
            ;;
        --test-api)
            if [ -n "$OPENAI_API_KEY" ]; then
                echo "Testing OpenAI API connection..."
                local test_response=$(call_openai_api "Respond with exactly: API_TEST_SUCCESS" 50 0.1)
                if [ $? -eq 0 ] && [[ "$test_response" == *"API_TEST_SUCCESS"* ]]; then
                    echo "✅ API connection successful"
                    return 0
                else
                    echo "❌ API test failed"
                    return 1
                fi
            else
                echo "❌ No API key found"
                return 1
            fi
            ;;
        *)
            echo "AI Helper for launchDevBench"
            echo "Usage: $0 [--recommend|--parse-recommendation|--analyze|--test-api] [args...]"
            ;;
    esac
}

main "$@"