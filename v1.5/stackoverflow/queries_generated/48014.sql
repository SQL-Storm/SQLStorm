-- {"query": "48014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 508} 

WITH RankedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL AND p.CreationDate >= DATE('now', '-1 year')
),
HighReputationUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS user_rn
    FROM Users u
    WHERE u.Id > 0
),
RecentCommentsOnTopQuestions AS (
    SELECT
        c.PostId,
        c.UserId,
        c.CreationDate,
        c.Score AS CommentScore,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS comment_rn
    FROM Comments c
    JOIN RankedQuestions rq ON c.PostId = rq.QuestionId
    WHERE rq.rn <= 100 AND c.CreationDate >= DATE('now', '-30 days')
)
SELECT
    rq.Title,
    rq.Score AS QuestionScore,
    rq.ViewCount AS QuestionViewCount,
    rq.FavoriteCount AS QuestionFavoriteCount,
    rq.OwnerDisplayName AS QuestionOwnerName,
    rq.Reputation AS QuestionOwnerReputation,
    hru.DisplayName AS TopUserDisplayName,
    hru.Reputation AS TopUserReputation,
    rc.CreationDate AS MostRecentCommentDate,
    rc.CommentScore AS MostRecentCommentScore
FROM RankedQuestions rq
LEFT JOIN HighReputationUsers hru ON hru.user_rn = rq.rn
LEFT JOIN RecentCommentsOnTopQuestions rc ON rq.QuestionId = rc.PostId AND rc.comment_rn = 1
WHERE rq.rn <= 100
ORDER BY rq.rn;
