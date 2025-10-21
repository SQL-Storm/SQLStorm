-- {"query": "44036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 630}

WITH cte AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        b.Id AS BadgeId,
        b.Name AS BadgeName,
        b.Date AS BadgeDate,
        b.Class AS BadgeClass,
        b.TagBased AS BadgeTagBased,
        v.Id AS VoteId,
        v.VoteTypeId,
        v.CreationDate AS VoteCreationDate,
        v.BountyAmount
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId
)
SELECT
    PostId,
    PostTypeId,
    ParentId,
    OwnerUserId,
    CreationDate,
    Score,
    ViewCount,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    ClosedDate,
    CommunityOwnedDate,
    Reputation,
    UserCreationDate,
    LastAccessDate,
    UserViews,
    UserUpVotes,
    UserDownVotes,
    BadgeId,
    BadgeName,
    BadgeDate,
    BadgeClass,
    BadgeTagBased,
    VoteId,
    VoteTypeId,
    VoteCreationDate,
    BountyAmount
FROM cte
ORDER BY PostId, BadgeDate DESC, VoteCreationDate DESC
```

This query performs a comprehensive performance benchmark of the StackOverflow database schema by joining multiple tables and extracting a wide range of data points related to posts, users, badges, and votes. The common table expression (CTE) consolidates the data from various tables, and the final query selects and orders the data based on the specified criteria. This query can be used to measure the performance of the database under various load conditions and identify potential bottlenecks.
