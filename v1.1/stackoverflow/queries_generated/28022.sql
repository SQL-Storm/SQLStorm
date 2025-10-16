-- {"query": "28022.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1526} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgPostScore,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate BETWEEN '2010-01-01' AND '2020-12-31'
    GROUP BY u.Id, u.Reputation, u.CreationDate
),
PostAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')) + 1 AS TagCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS TotalComments,
        FIRST_VALUE(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS FirstPostScore,
        LEAD(p.Title, 2) OVER (ORDER BY p.CreationDate) AS FutureTitle
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) AND p.Score > 0
)
SELECT 
    us.UserId,
    us.Reputation,
    us.BadgeCount,
    pa.PostId,
    pa.TagCount,
    pa.Upvotes,
    pa.TotalComments,
    COALESCE(ph.CreationDate, us.CreationDate) AS ActivityDate,
    CASE 
        WHEN ph.PostHistoryTypeId = 2 THEN SUBSTRING(ph.Text FROM 1 FOR 100)
        WHEN ph.PostHistoryTypeId = 5 THEN REPLACE(ph.Text, '\n', ' ')
        ELSE NULL
    END AS HistoryPreview,
    (SELECT STRING_AGG(TagName, '; ') 
     FROM Tags t 
     WHERE EXISTS (SELECT 1 FROM regexp_split_to_table(REPLACE(REPLACE(p.Tags, '<', ''), '>', ' '), ' ') AS tag WHERE tag = t.TagName)
    ) AS TagNames,
    ROUND((us.AnswersPosted * 1.0 / NULLIF(us.QuestionsPosted, 0)), 2) AS AnswerToQuestionRatio
FROM UserStats us
LEFT JOIN PostAnalysis pa ON us.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = pa.PostId)
LEFT JOIN PostHistory ph ON pa.PostId = ph.PostId AND ph.PostHistoryTypeId IN (2,5)
LEFT JOIN Posts p ON pa.PostId = p.Id
WHERE us.Reputation > 1000
    AND (us.BadgeCount > (SELECT AVG(BadgeCount) FROM UserStats) OR us.AvgPostScore > 5)
    AND (pa.TagCount BETWEEN 1 AND 5 OR pa.TagCount IS NULL)
    AND (pa.FutureTitle LIKE '%SQL%' OR pa.FutureTitle IS NULL)
UNION ALL
SELECT 
    NULL AS UserId,
    NULL AS Reputation,
    COUNT(*) AS BadgeCount,
    NULL AS PostId,
    NULL AS TagCount,
    NULL AS Upvotes,
    NULL AS TotalComments,
    MAX(CreationDate) AS ActivityDate,
    NULL AS HistoryPreview,
    'SYSTEM' AS TagNames,
    NULL AS AnswerToQuestionRatio
FROM PostHistory
WHERE PostHistoryTypeId = 50
ORDER BY Reputation DESC NULLS LAST, ActivityDate DESC;
