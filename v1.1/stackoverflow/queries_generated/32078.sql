-- {"query": "32078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 480} 

WITH UserBadges AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalViews,
        COUNT(DISTINCT p.Id) AS TotalPosts
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id
),
PostInteractions AS (
    SELECT
        p.Id AS PostId,
        COUNT(v.Id) AS TotalVotes,
        COUNT(distinct c.Id) AS TotalComments,
        COUNT(pl.Id) AS TotalLinks
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    GROUP BY p.Id
)
SELECT
    u.Id,
    u.DisplayName,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ua.TotalScore,
    ua.TotalCommentScore,
    ua.TotalViews,
    ua.TotalPosts,
    pi.TotalVotes,
    pi.TotalComments,
    pi.TotalLinks
FROM Users u
INNER JOIN UserBadges ub ON u.Id = ub.UserId
INNER JOIN UserActivity ua ON u.Id = ua.UserId
LEFT JOIN PostInteractions pi ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = pi.PostId)
WHERE u.Reputation > 2000
ORDER BY ua.TotalScore DESC, ub.GoldBadges DESC;
