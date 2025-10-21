WITH UserStats AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScore,
        SUM(p.ViewCount) AS TotalViewCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY
        u.Id,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes
),
PostActivity AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.LastActivityDate,
        COUNT(c.Id) AS TotalComments,
        COUNT(v.Id) AS TotalVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM
        Posts p
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    GROUP BY
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.LastActivityDate
),
BadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM
        Badges b
    GROUP BY
        b.UserId
)
SELECT
    us.UserId,
    us.Reputation,
    us.UserCreationDate,
    us.LastAccessDate,
    us.Views,
    us.UpVotes,
    us.DownVotes,
    us.TotalPosts,
    us.TotalQuestions,
    us.TotalAnswers,
    us.QuestionScore,
    us.AnswerScore,
    us.TotalViewCount,
    us.LastPostDate,
    pa.PostId,
    pa.PostTypeId,
    pa.CreationDate AS PostCreationDate,
    pa.Score AS PostScore,
    pa.ViewCount AS PostViewCount,
    pa.TotalComments,
    pa.TotalVotes,
    pa.TotalUpVotes,
    pa.TotalDownVotes,
    bs.TotalBadges,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges
FROM
    UserStats us
LEFT JOIN
    PostActivity pa ON us.UserId = pa.OwnerUserId
LEFT JOIN
    BadgeSummary bs ON us.UserId = bs.UserId
ORDER BY
    us.Reputation DESC,
    us.TotalPosts DESC,
    pa.Score DESC,
    bs.TotalBadges DESC
LIMIT 100;