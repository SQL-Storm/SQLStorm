-- {"query": "4062.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 870}
WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS rn_score,
        RANK() OVER (ORDER BY p.CreationDate ASC) AS rnk_date,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS next_day_score
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.Score > 0
),
UserPostEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 5
),
CommentSentiment AS (
    SELECT
        c.PostId,
        AVG(CASE
                WHEN c.Text LIKE '%great%' OR c.Text LIKE '%excellent%' OR c.Text LIKE '%thanks%' THEN 1
                WHEN c.Text LIKE '%bad%' OR c.Text LIKE '%terrible%' OR c.Text LIKE '%unhelpful%' THEN -1
                ELSE 0
            END) AS sentiment_score
    FROM Comments c
    WHERE c.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '3 months')
    GROUP BY c.PostId
)
SELECT
    rp.Id AS PostId,
    pt.Name AS PostTypeName,
    u.DisplayName AS OwnerDisplayName,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    COALESCE(cs.sentiment_score, 0) AS comment_sentiment,
    CASE
        WHEN rp.rn_score <= 10 THEN 'Top Question'
        WHEN rp.rn_score <= 50 THEN 'High Scored Question'
        ELSE 'Average Question'
    END AS PostRankByCategory,
    rp.rnk_date,
    rp.next_day_score,
    COALESCE(upe.AnswerCount, 0) AS UserAnswerCountInPastYear,
    COALESCE(upe.AvgPostScore, 0.0) AS UserAvgScoreInPastYear,
    CASE
        WHEN rp.Id = p_accepted.AcceptedAnswerId THEN 'Yes'
        ELSE 'No'
    END AS IsAcceptedAnswerPost,
    CASE
        WHEN p_accepted.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS PostStatus,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id AND c.Score > 5) AS HighScoreCommentCount
FROM RankedPosts rp
JOIN PostTypes pt ON rp.PostTypeId = pt.Id
LEFT JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN CommentSentiment cs ON rp.Id = cs.PostId
LEFT JOIN Posts p_accepted ON rp.Id = p_accepted.Id
LEFT JOIN UserPostEngagement upe ON rp.OwnerUserId = upe.UserId
WHERE rp.Title IS NOT NULL
  AND LENGTH(rp.Title) > 10
  AND rp.Score > (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.PostTypeId = 1)
ORDER BY rp.CreationDate DESC
LIMIT 100;