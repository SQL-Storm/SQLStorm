-- {"query": "14096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 758}
WITH cte AS (
    SELECT p.Id, p.PostTypeId, p.ParentId, p.CreationDate, p.Score, p.OwnerUserId, p.LastActivityDate,
           CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE NULL END AS AnswerCount,
           CASE WHEN p.PostTypeId = 1 THEN p.ClosedDate ELSE NULL END AS ClosedDate,
           CASE WHEN p.PostTypeId = 1 THEN p.FavoriteCount ELSE NULL END AS FavoriteCount,
           CASE WHEN p.PostTypeId = 1 THEN p.Title ELSE NULL END AS Title,
           CASE WHEN p.PostTypeId = 1 THEN p.Tags ELSE NULL END AS Tags,
           CASE WHEN p.PostTypeId = 2 THEN p.Body ELSE NULL END AS AnswerBody,
           CASE WHEN p.PostTypeId = 1 THEN p.Body ELSE NULL END AS QuestionBody,
           COALESCE(CAST(SUBSTRING(p.Body, 1, POSITION('<' IN p.Body) - 1) AS VARCHAR(100)), '') AS ShortenedBody
    FROM Posts p
),
cte2 AS (
    SELECT c.Id, c.PostId, c.Score, c.Text, c.CreationDate, c.UserDisplayName, c.UserId
    FROM Comments c
),
cte3 AS (
    SELECT v.Id, v.PostId, v.VoteTypeId, v.UserId, v.CreationDate
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3)
)
SELECT
    cte.Id,
    cte.PostTypeId,
    cte.ParentId,
    cte.CreationDate,
    cte.Score,
    cte.OwnerUserId,
    cte.LastActivityDate,
    cte.AnswerCount,
    cte.ClosedDate,
    cte.FavoriteCount,
    cte.Title,
    cte.Tags,
    cte.AnswerBody,
    cte.QuestionBody,
    cte.ShortenedBody,
    cte2.Id AS CommentId,
    cte2.Score AS CommentScore,
    cte2.Text AS CommentText,
    cte2.CreationDate AS CommentCreationDate,
    cte2.UserDisplayName AS CommentUserDisplayName,
    cte2.UserId AS CommentUserId,
    cte3.Id AS VoteId,
    cte3.VoteTypeId,
    cte3.UserId AS VoteUserId,
    cte3.CreationDate AS VoteCreationDate
FROM cte
LEFT JOIN cte2 ON cte.Id = cte2.PostId
LEFT JOIN cte3 ON cte.Id = cte3.PostId
ORDER BY cte.Id, cte2.Id, cte3.Id;
