-- {"query": "53037.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 572} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT ph.Id) AS EditCount,
        STRING_AGG(DISTINCT t.TagName, ', ') AS TopTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)  -- Upvotes and Downvotes
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1  -- Gold badges only
    LEFT JOIN Comments c ON p.Id = c.PostId AND c.UserId = u.Id
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)  -- Edits
    LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE u.Reputation > 1000
      AND p.CreationDate >= '2020-01-01'
      AND t.Count > 1000  -- Popular tags
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 50
),
RankedUsers AS (
    SELECT 
        ua.*,
        RANK() OVER (ORDER BY ua.TotalScore DESC) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY ua.QuestionCount ORDER BY ua.AvgScore DESC) AS AvgScoreRankPerQuestionGroup
    FROM UserActivity ua
)
SELECT 
    ru.UserId,
    ru.Reputation,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.TotalScore,
    ru.AvgScore,
    ru.VoteCount,
    ru.BadgeCount,
    ru.CommentCount,
    ru.EditCount,
    ru.TopTags,
    ru.ScoreRank,
    ru.AvgScoreRankPerQuestionGroup,
    (SELECT COUNT(pl.Id) FROM PostLinks pl WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = ru.UserId) AND pl.LinkTypeId = 3) AS DuplicateLinks  -- Subquery for duplicate links
FROM RankedUsers ru
WHERE ru.ScoreRank <= 100
ORDER BY ru.ScoreRank;