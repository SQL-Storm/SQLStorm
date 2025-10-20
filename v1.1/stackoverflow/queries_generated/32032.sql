-- {"query": "32032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 335} 

WITH RecursiveCTE AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.Body,
        ARRAY[CAST(p.Id AS INT)] AS Path,
        0 AS Level
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1

    UNION ALL

    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.Body,
        rcte.Path || p.Id AS Path,
        rcte.Level + 1 AS Level
    FROM
        Posts p
    INNER JOIN PostLinks pl ON p.Id = pl.RelatedPostId
    INNER JOIN RecursiveCTE rcte ON pl.PostId = rcte.Id
    WHERE
        p.PostTypeId = 1
        AND rcte.Level < 3
)

SELECT 
    u.DisplayName,
    u.Reputation,
    Count(RecursiveCTE.Id) AS TotalPosts,
    Max(RecursiveCTE.Score) AS MaxScore,
    Min(RecursiveCTE.CreationDate) AS FirstPostDate,
    Avg(char_length(RecursiveCTE.Body)) AS AvgBodyLength
FROM 
    RecursiveCTE
JOIN 
    Users u ON u.Id = RecursiveCTE.OwnerUserId
GROUP BY 
    u.DisplayName, u.Reputation
HAVING 
    Count(RecursiveCTE.Id) > 5
ORDER BY 
    TotalPosts DESC, MaxScore DESC, u.Reputation DESC
LIMIT 10;
