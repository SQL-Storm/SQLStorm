-- {"query": "1072.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 487} 

WITH UserReputation AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM
        Users u
), PostStatistics AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpvoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvoteCount,
        COUNT(c.Id) AS CommentCount
    FROM
        Posts p
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    GROUP BY
        p.Id
), TopPosts AS (
    SELECT
        ps.PostId,
        ps.Title,
        ps.Score,
        ps.UpvoteCount,
        ps.DownvoteCount,
        ps.CommentCount,
        u.Reputation AS UserReputation,
        u.DisplayName
    FROM
        PostStatistics ps
    JOIN
        Users u ON ps.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = u.Id)
    WHERE
        CommentCount > 5 AND Score > 10
)
SELECT
    tp.Title,
    tp.Score,
    tp.UserReputation,
    tp.DisplayName,
    tp.UpvoteCount - tp.DownvoteCount AS NetVotes,
    CASE
        WHEN tp.UserReputation > 1000 THEN 'High Reputation'
        WHEN tp.UserReputation BETWEEN 500 AND 1000 THEN 'Medium Reputation'
        ELSE 'Low Reputation' 
    END AS ReputationCategory,
    pl.RelatedPosts
FROM
    TopPosts tp
LEFT JOIN LATERAL (
    SELECT
        STRING_AGG(CONCAT('Related Post: ', p.Title), ', ') AS RelatedPosts
    FROM
        PostLinks pl
    JOIN
        Posts p ON pl.RelatedPostId = p.Id
    WHERE
        pl.PostId = tp.PostId
) pl ON TRUE
ORDER BY
    tp.Score DESC, tp.UserReputation DESC
LIMIT 100;
