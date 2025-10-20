-- {"query": "27099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1321} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(MAX(p.Score), 0) AS MaxPostScore,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(AVG(p.Score), 0) AS AvgPostScore,
        LAST_VALUE(p.LastActivityDate) OVER (PARTITION BY u.Id ORDER BY p.LastActivityDate DESC) AS LastPostActivity
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
RecentPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.PostTypeId,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        a.AcceptedAnswerId,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS RankByScore
    FROM
        Posts p
    JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        Posts a ON p.AcceptedAnswerId = a.Id
    WHERE
        p.CreationDate > NOW() - INTERVAL '30 days'
),
BadgeSummary AS (
    SELECT
        b.UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 THEN 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate,
        SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS TagBasedBadges
    FROM
        Badges b
    JOIN
        Users u ON b.UserId = u.Id
    GROUP BY
        b.UserId, u.DisplayName
),
HighActivityUsers AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.TotalPosts,
        ua.TotalComments,
        ua.TotalQuestions,
        ua.TotalAnswers,
        ua.MaxPostScore,
        ua.TotalPostScore,
        ua.AvgPostScore,
        ua.LastPostActivity,
        bs.TotalBadges,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        bs.LastBadgeDate,
        bs.TagBasedBadges,
        RANK() OVER (ORDER BY ua.TotalPosts + ua.TotalComments DESC) AS ActivityRank
    FROM
        UserActivity ua
    JOIN
        BadgeSummary bs ON ua.UserId = bs.UserId
)
SELECT
    ha.UserId,
    ha.DisplayName,
    ha.TotalPosts,
    ha.TotalComments,
    ha.TotalQuestions,
    ha.TotalAnswers,
    ha.MaxPostScore,
    ha.TotalPostScore,
    ha.AvgPostScore,
    ha.LastPostActivity,
    ha.TotalBadges,
    ha.GoldBadges,
    ha.SilverBadges,
    ha.BronzeBadges,
    ha.LastBadgeDate,
    ha.TagBasedBadges,
    ha.ActivityRank,
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.PostTypeId,
    rp.OwnerDisplayName,
    rp.AcceptedAnswerId,
    rp.PreviousScore,
    rp.NextScore,
    rp.RankByScore
FROM
    HighActivityUsers ha
LEFT JOIN
    RecentPosts rp ON ha.UserId = rp.OwnerUserId
WHERE
    ha.ActivityRank <= 100
    AND rp.Score IS NOT NULL
    AND rp.Title LIKE '%performance%'
ORDER BY
    ha.ActivityRank ASC,
    rp.Score DESC;
