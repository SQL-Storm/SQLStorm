-- {"query": "27021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 998} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT a.Id) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(v.CreationDate) AS LastVoteDate,
        MAX(b.Date) AS LastBadgeDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS ReputationRank
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.Reputation, u.DisplayName, u.LastAccessDate
),
TopPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.Tags,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    WHERE
        p.PostTypeId = 1
),
ActiveUsers AS (
    SELECT
        ua.UserId,
        ua.Reputation,
        ua.DisplayName,
        ua.TotalPosts,
        ua.TotalAnswers,
        ua.TotalComments,
        ua.TotalVotes,
        ua.TotalBadges,
        ua.LastPostDate,
        ua.LastCommentDate,
        ua.LastVoteDate,
        ua.LastBadgeDate,
        ua.ReputationRank
    FROM
        UserActivity ua
    WHERE
        ua.ReputationRank <= 100
)
SELECT
    au.UserId,
    au.DisplayName,
    au.Reputation,
    au.TotalPosts,
    au.TotalAnswers,
    au.TotalComments,
    au.TotalVotes,
    au.TotalBadges,
    au.LastPostDate,
    au.LastCommentDate,
    au.LastVoteDate,
    au.LastBadgeDate,
    tp.PostId,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    tp.AnswerCount,
    tp.CommentCount,
    tp.CreationDate,
    tp.PostRank,
    tp.Tags,
    (CASE
        WHEN tp.OwnerUserId IS NOT NULL THEN 'Owner'
        ELSE 'Not Owner'
     END) AS OwnershipStatus,
    COALESCE(NULLIF(SUBSTRING(tp.Tags, 2, LENGTH(tp.Tags) - 2), ''), 'No Tags') AS TagsList
FROM
    ActiveUsers au
LEFT JOIN
    TopPosts tp ON au.UserId = tp.OwnerUserId
WHERE
    au.Reputation > 5000
    AND (tp.PostRank IS NOT NULL OR au.TotalPosts > 100)
ORDER BY
    au.Reputation DESC, tp.PostRank;
