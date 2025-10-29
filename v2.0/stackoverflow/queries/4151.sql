-- {"query": "4151.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 901}
WITH RankedAnswers AS (
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 2
),
HighScoringQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.FavoriteCount,
        p.AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '365' DAY)
    GROUP BY p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.FavoriteCount, p.AnswerCount
    HAVING COUNT(v.Id) > 50
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT ph.Id) AS PostHistoryCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        MAX(ph.CreationDate) AS LastActivityDate
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT ph.Id) > 100 OR COUNT(DISTINCT c.Id) > 500
)
SELECT
    hq.QuestionId,
    hq.Title,
    hq.CreationDate AS QuestionCreationDate,
    hq.FavoriteCount,
    hq.AnswerCount,
    ua.DisplayName AS QuestionOwnerDisplayName,
    ua.Reputation AS QuestionOwnerReputation,
    ra.AnswerId AS BestAnswerId,
    ra.Score AS BestAnswerScore,
    ra.CreationDate AS BestAnswerCreationDate,
    ua_ans.DisplayName AS BestAnswerOwnerDisplayName,
    ua_ans.Reputation AS BestAnswerOwnerReputation,
    COALESCE(ph.Comment, 'No Close Comment') AS CloseReasonIfClosed,
    CASE
        WHEN p_closed.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS PostStatus,
    CASE
        WHEN ra.rn = 1 AND ra.Score > 10 THEN 'Top Answer'
        WHEN ra.rn <= 5 AND ra.Score > 0 THEN 'Among Top Answers'
        ELSE 'Other Answer'
    END AS AnswerRankCategory,
    (COALESCE(ua.DisplayName, 'Unknown User') || ' asked ' || hq.Title) AS QuestionSummary,
    (hq.TotalUpVotes - hq.TotalDownVotes) AS NetVoteScore
FROM HighScoringQuestions hq
LEFT JOIN UserActivity ua ON hq.OwnerUserId = ua.UserId
LEFT JOIN RankedAnswers ra ON hq.QuestionId = ra.QuestionId AND ra.rn = 1
LEFT JOIN UserActivity ua_ans ON ra.OwnerUserId = ua_ans.UserId
LEFT JOIN Posts p_closed ON hq.QuestionId = p_closed.Id AND p_closed.ClosedDate IS NOT NULL
LEFT JOIN PostHistory ph ON hq.QuestionId = ph.PostId AND ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL
WHERE hq.TotalUpVotes > hq.TotalDownVotes * 2
GROUP BY
    hq.QuestionId,
    hq.Title,
    hq.CreationDate,
    hq.FavoriteCount,
    hq.AnswerCount,
    ua.DisplayName,
    ua.Reputation,
    ra.AnswerId,
    ra.Score,
    ra.CreationDate,
    ua_ans.DisplayName,
    ua_ans.Reputation,
    ph.Comment,
    p_closed.ClosedDate,
    ra.rn,
    hq.TotalUpVotes,
    hq.TotalDownVotes
ORDER BY hq.CreationDate DESC
LIMIT 100;