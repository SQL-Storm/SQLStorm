-- {"query": "27084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1630} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS TotalPosts,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.Reputation DESC) AS ReputationRank
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
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
HighReputationUsers AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        UserCreationDate,
        TotalPosts,
        TotalScore,
        TotalComments,
        TotalVotes,
        TotalQuestions,
        TotalAnswers,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        ReputationRank
    FROM
        UserActivity
    WHERE
        Reputation > 10000
),
RecentActivity AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        u.DisplayName AS OwnerDisplayName,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountInPost,
        COUNT(v.Id) OVER (PARTITION BY p.Id) AS VoteCountInPost,
        LAG(p.ViewCount, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousViewCount,
        LEAD(p.ViewCount, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextViewCount
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    WHERE
        p.CreationDate > DATEADD(MONTH, -3, GETDATE())
),
TopPosts AS (
    SELECT
        PostId,
        PostCreationDate,
        Score,
        ViewCount,
        Title,
        Tags,
        AnswerCount,
        CommentCount,
        OwnerDisplayName,
        PreviousScore,
        NextScore,
        CommentCountInPost,
        VoteCountInPost,
        PreviousViewCount,
        NextViewCount
    FROM
        RecentActivity
    WHERE
        Score > 100 AND ViewCount > 5000
)
SELECT
    hru.UserId,
    hru.DisplayName,
    hru.Reputation,
    hru.UserCreationDate,
    hru.TotalPosts,
    hru.TotalScore,
    hru.TotalComments,
    hru.TotalVotes,
    hru.TotalQuestions,
    hru.TotalAnswers,
    hru.GoldBadges,
    hru.SilverBadges,
    hru.BronzeBadges,
    hru.ReputationRank,
    tp.PostId,
    tp.PostCreationDate,
    tp.Score,
    tp.ViewCount,
    tp.Title,
    tp.Tags,
    tp.AnswerCount,
    tp.CommentCount,
    tp.OwnerDisplayName,
    tp.PreviousScore,
    tp.NextScore,
    tp.CommentCountInPost,
    tp.VoteCountInPost,
    tp.PreviousViewCount,
    tp.NextViewCount
FROM
    HighReputationUsers hru
INNER JOIN
    TopPosts tp ON hru.UserId = tp.OwnerUserId
UNION
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.TotalPosts,
    ua.TotalScore,
    ua.TotalComments,
    ua.TotalVotes,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.ReputationRank,
    ra.PostId,
    ra.PostCreationDate,
    ra.Score,
    ra.ViewCount,
    ra.Title,
    ra.Tags,
    ra.AnswerCount,
    ra.CommentCount,
    ra.OwnerDisplayName,
    ra.PreviousScore,
    ra.NextScore,
    ra.CommentCountInPost,
    ra.VoteCountInPost,
    ra.PreviousViewCount,
    ra.NextViewCount
FROM
    UserActivity ua
INNER JOIN
    RecentActivity ra ON ua.UserId = ra.OwnerUserId
WHERE
    ua.Reputation BETWEEN 1000 AND 10000
ORDER BY
    ReputationRank, Score DESC, ViewCount DESC
LIMIT
    100;
