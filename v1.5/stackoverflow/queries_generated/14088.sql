-- {"query": "14088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 797}
WITH cte AS (
    SELECT p.Id, p.PostTypeId, p.Title, p.CreationDate, p.OwnerUserId, p.Score, p.AnswerCount, p.CommentCount,
           CASE
               WHEN p.PostTypeId = 1 THEN p.AcceptedAnswerId
               WHEN p.PostTypeId = 2 THEN p.ParentId
           END AS RelatedPostId,
           COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
           DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS OwnerScoreRank
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
closed_posts AS (
    SELECT p.Id, p.PostTypeId, p.Title, p.CreationDate, p.OwnerUserId, p.Score, p.AnswerCount, p.CommentCount,
           p.RelatedPostId, p.OwnerDisplayName, p.OwnerScoreRank,
           ph.Comment AS CloseReason
    FROM cte p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    WHERE ph.Comment IS NOT NULL
)
SELECT
    c.Id, c.PostTypeId, c.Title, c.CreationDate, c.OwnerUserId, c.Score, c.AnswerCount, c.CommentCount,
    c.RelatedPostId, c.OwnerDisplayName, c.OwnerScoreRank, c.CloseReason,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.Id AND v.VoteTypeId = 3) AS DownVotes,
    CASE
        WHEN c.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.Id AND v.VoteTypeId = 1)
        ELSE NULL
    END AS AcceptedAnswerVotes,
    CASE
        WHEN c.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Comments cm WHERE cm.PostId = c.Id)
        ELSE (SELECT COUNT(*) FROM Comments cm WHERE cm.PostId = c.RelatedPostId)
    END AS CommentCount2,
    CASE
        WHEN c.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.Id AND v.VoteTypeId = 5)
        ELSE (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.RelatedPostId AND v.VoteTypeId = 5)
    END AS FavoriteCount,
    CASE
        WHEN c.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Posts p WHERE p.ParentId = c.Id)
        ELSE 0
    END AS AnswerCount2
FROM closed_posts c
ORDER BY c.OwnerScoreRank, c.Score DESC;
