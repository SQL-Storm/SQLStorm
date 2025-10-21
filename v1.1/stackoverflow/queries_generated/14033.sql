-- {"query": "14033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 976}
WITH cte AS (
    SELECT p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, 
           u.Reputation, u.CreationDate AS UserCreationDate, u.UpVotes, u.DownVotes,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
           SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
           SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCount,
           STRING_AGG(DISTINCT t.TagName, '|') AS Tags
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN (
        SELECT PostId, STRING_AGG(DISTINCT SUBSTRING(Tags, 2, LENGTH(Tags) - 2), '|') AS TagName
        FROM Posts
        GROUP BY PostId
    ) t ON p.Id = t.PostId
    GROUP BY p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, 
             u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes
),
cte2 AS (
    SELECT c.Id, c.PostId, c.Score, c.CreationDate, c.UserId, c.UserDisplayName
    FROM Comments c
    WHERE c.PostId IN (SELECT Id FROM cte)
),
cte3 AS (
    SELECT b.Id, b.UserId, b.Name, b.Date, b.Class, b.TagBased
    FROM Badges b
    WHERE b.UserId IN (SELECT DISTINCT OwnerUserId FROM Posts WHERE Id IN (SELECT Id FROM cte))
)
SELECT 
    c.Id AS CommentId, c.PostId, c.Score AS CommentScore, c.CreationDate AS CommentCreationDate, c.UserId AS CommentUserId, c.UserDisplayName AS CommentUserDisplayName,
    p.Id AS PostId, p.PostTypeId, p.CreationDate AS PostCreationDate, p.Score AS PostScore, p.ViewCount AS PostViewCount, p.AnswerCount AS PostAnswerCount, p.FavoriteCount AS PostFavoriteCount,
    u.Id AS UserId, u.Reputation, u.CreationDate AS UserCreationDate, u.UpVotes, u.DownVotes, u.DisplayName AS UserDisplayName,
    b.Id AS BadgeId, b.UserId AS BadgeUserId, b.Name AS BadgeName, b.Date AS BadgeDate, b.Class AS BadgeClass, b.TagBased AS BadgeTagBased,
    p.Tags,
    COALESCE(c.UpvoteCount, 0) AS PostUpvoteCount,
    COALESCE(c.DownvoteCount, 0) AS PostDownvoteCount,
    COALESCE(c.AcceptedAnswerCount, 0) AS PostAcceptedAnswerCount,
    COALESCE(c.FavoriteCount, 0) AS PostFavoriteCount
FROM cte c
LEFT JOIN cte2 c2 ON c.Id = c2.PostId
LEFT JOIN Users u ON c.OwnerUserId = u.Id
LEFT JOIN cte3 b ON u.Id = b.UserId
ORDER BY c.Id, c.CreationDate, b.Date;
