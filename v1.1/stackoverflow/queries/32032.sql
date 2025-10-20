WITH RECURSIVE RecursiveCTE AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.Body,
        CAST(ARRAY[p.Id] AS INTEGER[]) AS Path,
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
        array_append(rcte.Path, p.Id) AS Path,
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
    COUNT(RecursiveCTE.Id) AS TotalPosts,
    MAX(RecursiveCTE.Score) AS MaxScore,
    MIN(RecursiveCTE.CreationDate) AS FirstPostDate,
    AVG(LENGTH(RecursiveCTE.Body)) AS AvgBodyLength,
    u.Id
FROM 
    RecursiveCTE
JOIN 
    Users u ON u.Id = RecursiveCTE.OwnerUserId
GROUP BY 
    u.DisplayName,
    u.Reputation,
    u.Id
HAVING 
    COUNT(RecursiveCTE.Id) > 5
ORDER BY 
    TotalPosts DESC, MaxScore DESC, u.Reputation DESC
LIMIT 10;