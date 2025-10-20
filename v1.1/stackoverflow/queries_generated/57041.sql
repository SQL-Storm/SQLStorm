-- {"query": "57041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 776} 

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
HighActivityUsers AS (
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
        LastBadgeDate,
        ROW_NUMBER() OVER (ORDER BY TotalPosts + TotalComments + TotalVotes DESC) AS ActivityRank
    FROM
        UserActivity
)
SELECT
    ha.UserId,
    ha.Reputation,
    ha.UserCreationDate,
    ha.TotalPosts,
    ha.TotalComments,
    ha.TotalVotes,
    ha.TotalBadges,
    ha.LastPostActivity,
    ha.LastCommentDate,
    ha.LastVoteDate,
    ha.LastBadgeDate,
    ha.ActivityRank,
    p.PostTypeId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount,
    c.Text AS LastCommentText,
    v.VoteTypeId,
    v.CreationDate AS VoteCreationDate,
    b.Name AS LastBadgeName,
    b.Class AS LastBadgeClass,
    t.TagName
FROM
    HighActivityUsers ha
LEFT JOIN
    Posts p ON ha.UserId = p.OwnerUserId AND p.CreationDate = ha.LastPostActivity
LEFT JOIN
    Comments c ON ha.UserId = c.UserId AND c.CreationDate = ha.LastCommentDate
LEFT JOIN
    Votes v ON ha.UserId = v.UserId AND v.CreationDate = ha.LastVoteDate
LEFT JOIN
    Badges b ON ha.UserId = b.UserId AND b.Date = ha.LastBadgeDate
LEFT JOIN
    Posts pt ON pt.Id = p.ParentId
LEFT JOIN
    Tags t ON p.Id = t.ExcerptPostId
WHERE
   ha.ActivityRank <= 100
ORDER BY
    ha.ActivityRank, p.Score DESC;
