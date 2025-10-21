-- {"query": "15011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 619}
WITH TagPopularity AS (
    SELECT 
        Tags.TagName, 
        Tags.Count,
        NTILE(10) OVER (ORDER BY Tags.Count DESC) AS PopularityTier,
        AVG(Posts.Score) OVER (PARTITION BY Tags.TagName) AS AvgTagScore
    FROM Tags
    JOIN Posts ON string_to_array(substring(Posts.Tags, 2, length(Posts.Tags)-2), '><') @> ARRAY[Tags.TagName]
),
UserContribution AS (
    SELECT 
        Users.Id AS UserId,
        Users.DisplayName,
        COUNT(DISTINCT Posts.Id) AS PostCount,
        SUM(Posts.Score) AS TotalScore,
        MAX(Posts.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT Posts.Id) DESC) AS PostRank
    FROM Users
    LEFT JOIN Posts ON Users.Id = Posts.OwnerUserId
    GROUP BY Users.Id, Users.DisplayName
)
SELECT 
    COALESCE(uc.DisplayName, 'Anonymous') AS UserName,
    tp.TagName,
    tp.PopularityTier,
    uc.PostCount,
    tp.AvgTagScore,
    CASE 
        WHEN uc.TotalScore > 1000 THEN 'High Impact'
        WHEN uc.TotalScore > 500 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS ContributionLevel,
    EXTRACT(YEAR FROM uc.LastPostDate) AS MostRecentYear,
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.UserId = uc.UserId AND v.VoteTypeId = 2) AS UpvoteCount
FROM UserContribution uc
JOIN TagPopularity tp ON 
    EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.OwnerUserId = uc.UserId 
        AND string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') @> ARRAY[tp.TagName]
    )
WHERE 
    uc.PostCount > 10 
    AND tp.PopularityTier <= 5
    AND (uc.TotalScore IS NULL OR uc.TotalScore > 0)
ORDER BY 
    tp.PopularityTier, 
    uc.PostCount DESC
LIMIT 500;
