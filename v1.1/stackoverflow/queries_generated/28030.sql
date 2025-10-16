-- {"query": "28030.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1113} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        RANK() OVER (ORDER BY AVG(p.AnswerCount) DESC) AS AnswerRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    GROUP BY u.Id
),
PostVotes AS (
    SELECT 
        p.Id,
        p.Title,
        p.Tags,
        (SELECT SUM(v.VoteTypeId) FROM Votes v WHERE v.PostId = p.Id) AS TotalVotes,
        (SELECT Score FROM Posts WHERE Id = p.AcceptedAnswerId) AS AcceptedAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 1
),
CommentAnalysis AS (
    SELECT 
        c.PostId,
        STRING_AGG(LEFT(c.Text, 50), '; ') AS CommentPreview,
        COUNT(*) FILTER (WHERE c.Score > 5) AS HighScoreComments
    FROM Comments c
    GROUP BY c.PostId
)
SELECT 
    u.Id AS UserId,
    COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
    pv.Title,
    pv.TotalVotes * 10 + COALESCE(pv.AcceptedAnswerScore, 0) AS EngagementScore,
    ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(pv.Tags, 2, LENGTH(pv.Tags)-2), '><'), 1) AS TagCount,
    ca.CommentPreview,
    us.BadgeCount,
    CASE 
        WHEN us.Reputation > 100000 THEN 'Legendary'
        WHEN us.Reputation > 50000 THEN 'Epic'
        ELSE 'Regular'
    END AS ReputationClass,
    (SELECT COUNT(*) FROM PostHistory ph 
     WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11, 12)) AS ModerationActions
FROM Users u
JOIN UserStats us ON u.Id = us.Id
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN PostVotes pv ON p.Id = pv.Id
LEFT JOIN CommentAnalysis ca ON p.Id = ca.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3
WHERE u.OwnerUserId IS NOT NULL
  AND (pv.Tags LIKE '%<sql>%' OR pv.Tags IS NULL)
  AND EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2)
INTERSECT
SELECT 
    u.Id,
    u.DisplayName,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM Users u
WHERE u.Id IN (SELECT UserId FROM Badges WHERE Class = 1)
UNION
SELECT 
    -1,
    'System',
    NULL,
    SUM(TotalVotes),
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM PostVotes
HAVING COUNT(*) > 1000
ORDER BY EngagementScore DESC NULLS LAST
LIMIT 100;
