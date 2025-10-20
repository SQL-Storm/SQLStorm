-- {"query": "57002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1048} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    WHERE
        u.CreationDate >= DATE('2023-01-01')
    GROUP BY
        u.Id, u.Reputation, u.CreationDate
),

PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COUNT(v.Id) AS TotalVotes,
        COUNT(c.Id) AS TotalComments,
        COUNT(DISTINCT ph.Id) AS TotalPostHistoryEntries
    FROM
        Posts p
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    WHERE
        p.CreationDate >= DATE('2023-01-01')
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount
),

TagActivity AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        COUNT(p.Id) AS PostsWithTag,
        COUNT(DISTINCT v.Id) AS TotalVotesOnTaggedPosts,
        COUNT(DISTINCT c.Id) AS TotalCommentsOnTaggedPosts
    FROM
        Tags t
    LEFT JOIN
        Posts p ON t.TagName = ANY(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ''><''))
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    GROUP BY
        t.Id, t.TagName, t.Count
)

SELECT
    ua.UserId,
    ua.Reputation,
    ua.UserCreationDate,
    ua.TotalPosts,
    ua.TotalComments,
    ua.TotalVotes,
    ua.TotalBadges,
    pe.PostId,
    pe.PostTypeId,
    pe.PostCreationDate,
    pe.Score,
    pe.ViewCount,
    pe.AnswerCount,
    pe.CommentCount,
    pe.FavoriteCount,
    pe.TotalVotes AS PostTotalVotes,
    pe.TotalComments AS PostTotalComments,
    pe.TotalPostHistoryEntries,
    ta.TagId,
    ta.TagName,
    ta.TagCount,
    ta.PostsWithTag,
    ta.TotalVotesOnTaggedPosts,
    ta.TotalCommentsOnTaggedPosts
FROM
    UserActivity ua
JOIN
    PostEngagement pe ON ua.UserId = pe.OwnerUserId
JOIN
    TagActivity ta ON pe.PostId = ta.TagId
WHERE
    ua.TotalPosts > 10 AND
    pe.ViewCount > 100 AND
    ta.PostsWithTag > 5
ORDER BY
    ua.Reputation DESC,
    pe.Score DESC,
    ta.TagCount DESC
LIMIT 100;
