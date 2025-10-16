-- {"query": "5087.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 995} 
WITH recent_questions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        p.Tags,
        p.ViewCount,
        p.Score,
        COALESCE(p.CommentCount, 0) AS CommentCount
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (SELECT MAX(CreationDate) FROM Posts WHERE PostTypeId = 1) - INTERVAL '30 day'
),
most_commented_answers AS (
    SELECT 
        a.ParentId AS QuestionId,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreation,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY COALESCE(a.CommentCount, 0) DESC, a.Score DESC) AS rn
    FROM Posts a
    WHERE a.PostTypeId = 2
      AND a.CommentCount IS NOT NULL
),
question_edit_info AS (
    SELECT 
        ph.PostId,
        ph.UserId AS EditorId,
        u.DisplayName AS EditorName,
        ph.CreationDate AS EditDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    LEFT JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- edits to title/body/tags
)
SELECT
    rq.QuestionId,
    rq.Title,
    rq.OwnerName,
    rq.CreationDate,
    rq.Tags,
    rq.ViewCount,
    rq.Score,
    rq.CommentCount,
    COUNT(DISTINCT c.Id) AS NumComments,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END), 0) AS NetVotes,
    (
        SELECT 
            STRING_AGG(DISTINCT t.TagName, ', ')
        FROM Tags t 
        WHERE ('<' || t.TagName || '>') = ANY (string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><'))
    ) AS TagNames,
    a.AnswerId AS TopCommentedAnswerId,
    a.AnswerScore AS TopAnswerScore,
    (CASE WHEN a.AnswerId IS NOT NULL THEN 1 ELSE 0 END) AS HasPopularAnswer,
    au.DisplayName AS TopAnswerOwner,
    qei.EditorName AS LastEditor,
    qei.EditDate AS LastEditDate,
    -- Complicated predicate: only show if user reputation is in top 20% or the post has at least 10 votes
    CASE
        WHEN u.Reputation >=
            (
                SELECT PERCENTILE_CONT(0.8) WITHIN GROUP (ORDER BY Reputation) FROM Users
            )
            OR (
                COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END), 0) >= 10
            )
        THEN 'Featured'
        ELSE 'Normal'
    END AS QuestionHighlight,
    -- Some NULL logic and calculations
    COALESCE((rq.ViewCount * 1.0 / NULLIF(rq.Score, 0)), 0) AS ViewScoreRatio,
    LEFT(rq.Title, 50) AS ShortTitle
FROM recent_questions rq
LEFT JOIN Comments c ON c.PostId = rq.QuestionId
LEFT JOIN Votes v ON v.PostId = rq.QuestionId
LEFT JOIN most_commented_answers a
    ON a.QuestionId = rq.QuestionId AND a.rn = 1
LEFT JOIN Users au ON a.AnswerOwnerId = au.Id
LEFT JOIN question_edit_info qei ON qei.PostId = rq.QuestionId AND qei.rn = 1
LEFT JOIN Users u ON rq.OwnerUserId = u.Id
WHERE
    rq.ViewCount > (
        SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1
    )
    AND (rq.Score > 0 OR rq.CommentCount >= 3)
GROUP BY
    rq.QuestionId, rq.Title, rq.OwnerName, rq.CreationDate, rq.Tags, rq.ViewCount, rq.Score, rq.CommentCount,
    a.AnswerId, a.AnswerScore, au.DisplayName, qei.EditorName, qei.EditDate, u.Reputation
ORDER BY
    rq.ViewCount DESC, NetVotes DESC
LIMIT 50;