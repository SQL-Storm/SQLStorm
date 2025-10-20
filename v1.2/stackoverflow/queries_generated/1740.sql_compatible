WITH RankedQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        u.DisplayName AS OwnerName,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.Id) AS rn
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
)
SELECT
    Id,
    Title,
    Tags,
    OwnerName,
    Reputation
FROM RankedQuestions
WHERE rn = 1;