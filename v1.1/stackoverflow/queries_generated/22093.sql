-- {"query": "22093.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 742} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(b.Id) AS BadgeCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    GROUP BY u.Id, u.Reputation
),
PostDetails AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        LENGTH(COALESCE(p.Body, '')) AS BodyLength,
        CASE WHEN p.Tags IS NOT NULL THEN array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1) ELSE 0 END AS TagCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveCommentCount,
        (SELECT SUM(vh.Score) 
         FROM (SELECT DISTINCT PostId, Score FROM Votes WHERE PostId = p.Id AND VoteTypeId = 2) vh) AS TotalUpvotes
    FROM Posts p
    WHERE p.PostTypeId = 1
),
BestAnswers AS (
    SELECT 
        pa.ParentId AS QuestionId,
        pa.Id AS AnswerId,
        pa.Score,
        pa.OwnerUserId,
        RANK() OVER (PARTITION BY pa.ParentId ORDER BY pa.Score DESC) AS ScoreRank
    FROM Posts pa
    WHERE pa.PostTypeId = 2
)
SELECT 
    pd.Id AS PostId,
    pd.Score AS QuestionScore,
    pd.ViewCount,
    pd.BodyLength,
    pd.TagCount,
    pd.PositiveCommentCount,
    COALESCE(pd.TotalUpvotes, 0) AS TotalUpvotes,
    us.UserId,
    us.Reputation,
    us.BadgeCount,
    us.UpvoteCount,
    ba.AnswerId AS BestAnswerId,
    ba.Score AS BestAnswerScore,
    CASE WHEN pd.AcceptedAnswerId != -1 THEN 'Accepted' ELSE 'Not Accepted' END AS AcceptanceStatus,
    ROUND((pd.Score + COALESCE(pd.TotalUpvotes, 0) + pd.PositiveCommentCount) * LOG(COALESCE(pd.ViewCount, 1) + 1), 2) AS ComputedInterestScore,
    CASE WHEN ba.Score IS NULL THEN 'No Answers' WHEN ba.Score < 5 THEN 'Low' WHEN ba.Score BETWEEN 5 AND 20 THEN 'Medium' ELSE 'High' END AS QualityTier
FROM PostDetails pd
INNER JOIN UserStats us ON pd.OwnerUserId = us.UserId
LEFT JOIN BestAnswers ba ON pd.Id = ba.QuestionId AND ba.ScoreRank = 1
WHERE us.RepRank <= 100
    AND pd.Score > 0
    AND (pd.BodyLength > 100 OR pd.TagCount > 3)
    AND EXISTS (
        SELECT 1 FROM PostLinks pl 
        WHERE pl.PostId = pd.Id OR pl.RelatedPostId = pd.Id
        AND pl.LinkTypeId = 1
    )
ORDER BY ComputedInterestScore DESC, QuestionScore DESC
LIMIT 50;