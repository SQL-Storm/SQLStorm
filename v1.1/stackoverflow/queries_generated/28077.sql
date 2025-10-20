-- {"query": "28077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1197} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        AVG(p.Score) AS AvgPostScore,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.LastActivityDate) AS LastActivity,
        RANK() OVER (PARTITION BY b.Class ORDER BY u.Reputation DESC) AS BadgeClassRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE p.PostTypeId IN (1,2)
    GROUP BY u.Id, b.Class
), PostAnalysis AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><') AS TagArray,
        LEAD(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostDate
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.ClosedDate IS NULL
    GROUP BY p.Id
)
SELECT 
    u.DisplayName,
    pa.Title,
    pa.Upvotes,
    COALESCE(pa.CommentCount,0) AS Comments,
    us.BadgeClassRank,
    (SELECT COUNT(*) FROM PostHistory ph 
     WHERE ph.PostId = pa.Id AND ph.PostHistoryTypeId = 10
     AND ph.Comment::int IN (101,102)) AS CloseAttempts,
    ARRAY_LENGTH(pa.TagArray, 1) AS TagCount,
    EXTRACT(DAY FROM pa.NextPostDate - p.CreationDate) AS DaysBetweenPosts,
    (SELECT STRING_AGG(t.TagName, '; ') 
     FROM Tags t 
     WHERE t.TagName = ANY(pa.TagArray) AND t.IsModeratorOnly = 1) AS ModeratorTags
FROM PostAnalysis pa
JOIN Posts p ON pa.Id = p.Id
JOIN UserStats us ON p.OwnerUserId = us.UserId
LEFT JOIN PostLinks pl ON pa.Id = pl.PostId AND pl.LinkTypeId = 3
WHERE pa.Score > 100
AND us.AvgPostScore > (SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Score) FROM Posts)
AND EXISTS (
    SELECT 1 
    FROM PostHistory ph 
    WHERE ph.PostId = pa.Id 
    AND ph.PostHistoryTypeId = 2 
    AND ph.Text ILIKE '%urgent%'
)
HAVING COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 3) < 3
ORDER BY us.BadgeClassRank, pa.Upvotes DESC
LIMIT 100;
