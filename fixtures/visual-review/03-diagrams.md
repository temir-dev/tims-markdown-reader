# A plan in diagrams

These examples render locally. Try changing the reading font and text size while this page is open. Give the diagrams a moment to redraw after moving the slider.

## From a note to a decision

```mermaid
flowchart LR
    A[Open the handoff] --> B[Read the summary]
    B --> C{Anything unclear?}
    C -->|Yes| D[Check the details]
    D --> B
    C -->|No| E[Close the window]
```

## A conversation between components

```mermaid
sequenceDiagram
    participant Person
    participant Reader
    participant File
    Person->>Reader: Open a Markdown document
    Reader->>File: Read its contents
    File-->>Reader: Markdown text
    Reader-->>Person: Show a reading page
    Person->>Reader: Choose a larger text size
    Reader-->>Person: Update the open page
```

## A document's day

```mermaid
stateDiagram-v2
    [*] --> Open
    Open --> Reading
    Reading --> Refreshed: Saved by another app
    Refreshed --> Reading
    Reading --> Closed
    Closed --> [*]
```

## An intentionally broken diagram

You should see a short error message here. The rest of the document should remain usable.

```mermaid
this is deliberately not valid diagram syntax
```

## Still here

This paragraph appears after the broken example. [Return to the sample list](00-start-here.md).
