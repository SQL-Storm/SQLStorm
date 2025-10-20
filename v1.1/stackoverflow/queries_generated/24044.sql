-- {"query": "24044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 4593} 
WITH TopUsers AS (
    SELECT u.Id AS UserId, u.Reputation
    FROM Users u
    WHERE u.Reputation > 5000
    UNION ALL
    SELECT u.Id AS UserId, u.Reputation
    FROM Users u
    WHERE u.Reputation BETWEEN 1000 AND 5000
      AND u.Views > 10000
),
RankedPosts AS (
    SELECT p.Id AS PostId,
           p.Title,
           p.Score,
           p.OwnerUserId,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM Posts p
    JOIN TopUsers tu ON p.OwnerUserId = tu.UserId
    WHERE p.PostTypeId = 1
),
PostVotes AS (
    SELECT ph.PostId,
           SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVotes,
           SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVotes
    FROM PostHistory ph
    GROUP BY ph.PostId
),
CommentsSummary AS (
    SELECT c.PostId,
           MIN(c.CreationDate) AS FirstCommentDate,
           COUNT(*) AS CommentCount
    FROM Comments c
    GROUP BY c.PostId
),
Final AS (
    SELECT p.PostId,
           p.Title,
           p.Score,
           p.PostRank,
           COALESCE(v.CloseVotes, 0) AS CloseVotes,
           COALESCE(v.ReopenVotes, 0) AS ReopenVotes,
           cs.CommentCount,
           cs.FirstCommentDate,
           CASE
               WHEN p.Score > 20
                    AND cs.CommentCount > 10
                    AND (SELECT COUNT(*) FROM PostHistory ph2
                         WHERE ph2.PostId = p.PostId
                           AND ph2.PostHistoryTypeId = 10) > 0
               THEN 'Hot'
               ELSE 'Normal'
           END AS PostCategory,
           tu.Reputation
    FROM RankedPosts p
    LEFT JOIN PostVotes v ON v.PostId = p.PostId
    LEFT JOIN CommentsSummary cs ON cs.PostId = p.PostId
    JOIN TopUsers tu ON tu.UserId = p.OwnerUserId
)
SELECT *
FROM Final
WHERE PostRank <= 3
  AND (
      Title LIKE '%SQL%' OR
      Title LIKE '%database%' OR
      Title LIKE '%performance%'
  )
ORDER BY Reputation DESC, Score DESC, CommentCount DESC
OFFSET 0 ROWS FETCH NEXT 500 ROWS ONLY;