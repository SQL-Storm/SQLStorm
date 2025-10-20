-- {"query": "57046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1084} 

WITH RecursiveUserHierarchy AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        1 AS Level
    FROM
        Users u
    WHERE
        u.Id = (SELECT MIN(Id) FROM Users)
    UNION ALL
    SELECT
        u.Id,
        u.Reputation,
        u.DisplayName,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        ruh.Level + 1
    FROM
        Users u
    INNER JOIN
        RecursiveUserHierarchy ruh
    ON
        u.AccountId = ruh.AccountId
    WHERE
        u.Id > ruh.UserId
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY t.Count DESC) AS Rank
    FROM
        Tags t
),
PostMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.OwnerUserId,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS TotalComments,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id) AS TotalEdits
    FROM
        Posts p
),
UserActivity AS (
    SELECT
        ruh.UserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViews,
        SUM(pm.UpVotes) AS TotalUpVotes,
        SUM(pm.DownVotes) AS TotalDownVotes,
        SUM(pm.TotalComments) AS TotalComments,
        SUM(pm.TotalEdits) AS TotalEdits
    FROM
        RecursiveUserHierarchy ruh
    LEFT JOIN
        Posts p
    ON
        p.OwnerUserId = ruh.UserId
    LEFT JOIN
        PostMetrics pm
    ON
        pm.PostId = p.Id
    GROUP BY
        ruh.UserId, ruh.Level
),
TopPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        pm.TotalComments,
        pm.TotalEdits,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY pm.TotalComments DESC, pm.TotalEdits DESC) AS Rank
    FROM
        Posts p
    INNER JOIN
        PostMetrics pm
    ON
        pm.PostId = p.Id
    WHERE
        p.PostTypeId = 1  -- Questions only
)
SELECT
    tt.TagName,
    tt.Count,
    tt.ExcerptPostId,
    tt.WikiPostId,
    tp.PostId,
    tp.Title,
    tp.TotalComments,
    tp.TotalEdits,
    ua.UserId,
    ua.TotalPosts,
    ua.TotalScore,
    ua.TotalViews,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.TotalComments AS UserTotalComments,
    ua.TotalEdits AS UserTotalEdits
FROM
    TopTags tt
LEFT JOIN
    TopPosts tp
ON
    tt.ExcerptPostId = tp.PostId
LEFT JOIN
    UserActivity ua
ON
    tp.OwnerUserId = ua.UserId
WHERE
    tt.Rank <= 10
    AND tp.Rank <= 5;
