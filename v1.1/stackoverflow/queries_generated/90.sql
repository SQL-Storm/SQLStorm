-- {"query": "90.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 130} 
WITH RecursiveCTE AS (
    SELECT Id, Name
    FROM PostTypes
    UNION ALL
    SELECT RT.Id, RT.Name
    FROM RecursiveCTE AS R
    JOIN PostHistoryTypes AS RT ON R.Id = RT.Id
)
SELECT PHT.Id, PHT.Name, LT.Name AS LinkTypeName
FROM RecursiveCTE
LEFT JOIN PostHistoryTypes AS PHT ON RecursiveCTE.Id = PHT.Id
LEFT JOIN LinkTypes AS LT ON RecursiveCTE.Id = LT.Id
WHERE PHT.Id IS NOT NULL or LT.Id IS NOT NULL
ORDER BY PHT.Id DESC, LT.Id ASC;