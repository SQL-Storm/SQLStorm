-- {"query": "57034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 949} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(v.CreationDate) AS LastVoteDate,
        MAX(b.Date) AS LastBadgeDate
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
    GROUP BY
        u.Id, u.Reputation, u.CreationDate
),
HighReputationUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        TotalPosts,
        TotalComments,
        TotalVotes,
        TotalBadges,
        LastPostActivity,
        LastCommentDate,
        LastVoteDate,
        LastBadgeDate
    FROM
        UserActivity
    WHERE
        Reputation > 10000
),
ActiveUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        TotalPosts,
        TotalComments,
        TotalVotes,
        TotalBadges,
        LastPostActivity,
        LastCommentDate,
        LastVoteDate,
        LastBadgeDate
    FROM
        HighReputationUsers
    WHERE
        LastPostActivity > NOW() - INTERVAL '30 days'
        OR LastCommentDate > NOW() - INTERVAL '30 days'
        OR LastVoteDate > NOW() - INTERVAL '30 days'
        OR LastBadgeDate > NOW() - INTERVAL '30 days'
)
SELECT
    a.UserId,
    a.Reputation,
    a.UserCreationDate,
    a.TotalPosts,
    a.TotalComments,
    a.TotalVotes,
    a.TotalBadges,
    a.LastPostActivity,
    a.LastCommentDate,
    a.LastVoteDate,
    a.LastBadgeDate,
    p.PostTypeId,
    p.Score AS PostScore,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.CreationDate AS PostCreationDate,
    p.LastActivityDate,
    p.Title,
    c.Score AS CommentScore,
    c.Text AS CommentText,
    c.CreationDate AS CommentCreationDate,
    v.VoteTypeId,
    v.CreationDate AS VoteCreationDate,
    b.Name AS BadgeName,
    b.Date AS BadgeDate,
    b.Class AS BadgeClass,
    b.TagBased
FROM
    ActiveUsers a
LEFT JOIN
    Posts p ON a.UserId = p.OwnerUserId
LEFT JOIN
    Comments c ON a.UserId = c.UserId
LEFT JOIN
    Votes v ON a.UserId = v.UserId
LEFT JOIN
    Badges b ON a.UserId = b.UserId
WHERE
    p.PostTypeId IN (1, 2)
    AND p.CreationDate > NOW() - INTERVAL '1 year'
    AND p.Score > 10
ORDER BY
    a.Reputation DESC,
    p.Score DESC,
    c.Score DESC,
    b.Date DESC;
