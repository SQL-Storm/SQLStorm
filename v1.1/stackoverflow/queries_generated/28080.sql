-- {"query": "28080.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1782} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(p.Score) OVER (PARTITION BY u.Location) AS AvgLocationScore,
        RANK() OVER (ORDER BY u.Reputation DESC) AS GlobalRank,
        RANK() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS LocalRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.Reputation, u.Location
),
PostAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.ClosedDate,
        STRING_AGG(SUBSTRING(t.Tags FROM 2 FOR LENGTH(t.Tags)-2), '><') AS CleanedTags,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS Upvotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS Downvotes,
        AVG(p.Score) OVER (ORDER BY p.CreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS MovingAvgScore,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 5) AS EditCount
    FROM Posts p
    LEFT JOIN Tags t ON p.Tags LIKE '%>' || t.TagName || '<%'
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.CreationDate
)
SELECT 
    u.Id,
    u.DisplayName,
    COALESCE(u.Location, 'Unknown') AS Location,
    CONCAT_WS(' - ', u.DisplayName, COALESCE(u.Location, 'Global')) AS UserIdentifier,
    us.BadgeCount,
    us.QuestionCount,
    us.AnswerCount,
    us.CommentCount,
    pa.Score,
    pa.CleanedTags,
    pa.Upvotes,
    pa.Downvotes,
    (pa.Upvotes * 1.0 / NULLIF(pa.Upvotes + pa.Downvotes, 0)) AS UpvoteRatio,
    pa.MovingAvgScore,
    pa.EditCount,
    us.AvgLocationScore,
    us.GlobalRank,
    us.LocalRank,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.ClosedDate IS NOT NULL) AS ClosedPosts,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = pa.PostId AND pl.LinkTypeId = 3) AS DuplicateLinks,
    CASE 
        WHEN u.Reputation > 100000 THEN 'Legendary' 
        WHEN u.Reputation BETWEEN 50000 AND 100000 THEN 'Epic' 
        WHEN u.Reputation BETWEEN 10000 AND 49999 THEN 'Veteran' 
        ELSE 'Member' 
    END AS ReputationTier,
    EXTRACT(YEAR FROM AGE(NOW(), u.CreationDate)) AS AccountAgeYears
FROM Users u
JOIN UserStats us ON u.Id = us.UserId
LEFT JOIN PostAnalysis pa ON u.Id = pa.OwnerUserId
WHERE u.Reputation > 1000
    AND (pa.ClosedDate IS NULL OR pa.ClosedDate > NOW() - INTERVAL '1 YEAR')
    AND EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1)
ORDER BY 
    us.GlobalRank, 
    pa.Score DESC NULLS LAST, 
    AccountAgeYears DESC
LIMIT 1000;
