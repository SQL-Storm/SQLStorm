-- {"query": "31043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 300} 

WITH RankedPosts AS (
    SELECT p.Id AS PostId, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName AS OwnerDisplayName,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS Rank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.Score IS NOT NULL
),
TopPosts AS (
    SELECT PostId, Title, CreationDate, Score, ViewCount, OwnerDisplayName
    FROM RankedPosts
    WHERE Rank <= 5
),
PostCommentCounts AS (
    SELECT PostId, COUNT(c.Id) AS CommentCount
    FROM Comments c
    GROUP BY PostId
),
PostVoteCounts AS (
    SELECT PostId, COUNT(v.Id) AS VoteCount
    FROM Votes v
    GROUP BY PostId
)
SELECT tp.Title, tp.CreationDate, tp.Score, tp.ViewCount, tp.OwnerDisplayName,
       COALESCE(pc.CommentCount, 0) AS TotalComments,
       COALESCE(vc.VoteCount, 0) AS TotalVotes
FROM TopPosts tp
LEFT JOIN PostCommentCounts pc ON tp.PostId = pc.PostId
LEFT JOIN PostVoteCounts vc ON tp.PostId = vc.PostId
ORDER BY tp.Score DESC, tp.ViewCount DESC;
