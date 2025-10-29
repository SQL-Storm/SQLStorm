WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id)                                            AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END)      AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END)      AS Answers,
        COALESCE(SUM(p.Score), 0)                              AS TotalScore,
        MAX(p.CreationDate)                                   AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeStats AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*)                                      AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
VoteStats AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes,
        MAX(v.CreationDate)                         AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
UserRecentActivity AS (
    SELECT 
        u.Id,
        GREATEST(
            COALESCE(us.LastPostDate,      TIMESTAMP '1900-01-01'),
            COALESCE(vs.LastVoteDate,     TIMESTAMP '1900-01-01'),
            COALESCE(u.LastAccessDate,   TIMESTAMP '1900-01-01')
        ) AS RecentActivity
    FROM Users u
    LEFT JOIN UserStats us ON us.Id = u.Id
    LEFT JOIN (
        SELECT 
            p.OwnerUserId AS UserId,
            MAX(vs.LastVoteDate) AS LastVoteDate
        FROM Posts p
        LEFT JOIN VoteStats vs ON vs.PostId = p.Id
        GROUP BY p.OwnerUserId
    ) vs ON vs.UserId = u.Id
)
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.TotalPosts,
    us.Questions,
    us.Answers,
    us.TotalScore,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.TotalBadges,
    ur.RecentActivity,
    ROW_NUMBER() OVER (ORDER BY us.TotalScore DESC)          AS ScoreRank,
    -- string_agg cannot be used as a window function in some engines; aggregate per user instead
    t.TagList,
    CASE 
        WHEN us.TotalScore > 1000 THEN 'Top Contributor'
        WHEN us.TotalScore BETWEEN 500 AND 1000 THEN 'Active Contributor'
        ELSE 'Casual Contributor'
    END                                                       AS ContributionLevel
FROM UserStats us
LEFT JOIN BadgeStats bs       ON bs.UserId = us.Id
LEFT JOIN UserRecentActivity ur ON ur.Id = us.Id
LEFT JOIN (
    SELECT
        OwnerUserId AS OwnerUserId,
        STRING_AGG(regexp_replace(Tags, '^<|>$', '', 'g'), ',') AS TagList
    FROM Posts
    WHERE Tags IS NOT NULL
    GROUP BY OwnerUserId
) t ON t.OwnerUserId = us.Id
LEFT JOIN Posts p             ON p.OwnerUserId = us.Id AND p.PostTypeId = 1
WHERE us.Reputation > 1000
  AND (bs.TotalBadges IS NULL OR bs.TotalBadges >= 5)
  AND EXISTS (
        SELECT 1 
        FROM Comments c 
        WHERE c.UserId = us.Id 
          AND c.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
      )
UNION ALL
SELECT
    CAST(NULL AS bigint) AS Id,
    'Aggregate' AS DisplayName,
    CAST(NULL AS bigint) AS Reputation,
    SUM(us.TotalPosts)   AS TotalPosts,
    SUM(us.Questions)    AS Questions,
    SUM(us.Answers)      AS Answers,
    SUM(us.TotalScore)   AS TotalScore,
    SUM(bs.GoldBadges)   AS GoldBadges,
    SUM(bs.SilverBadges) AS SilverBadges,
    SUM(bs.BronzeBadges) AS BronzeBadges,
    SUM(bs.TotalBadges)  AS TotalBadges,
    MAX(ur.RecentActivity) AS RecentActivity,
    CAST(NULL AS bigint) AS ScoreRank,
    CAST(NULL AS text) AS TagList,
    CAST(NULL AS text) AS ContributionLevel
FROM UserStats us
LEFT JOIN BadgeStats bs       ON bs.UserId = us.Id
LEFT JOIN UserRecentActivity ur ON ur.Id = us.Id
WHERE us.Reputation > 1000
EXCEPT
SELECT 
    CAST(us.Id AS bigint) AS Id,
    us.DisplayName,
    CAST(us.Reputation AS bigint) AS Reputation,
    us.TotalPosts,
    us.Questions,
    us.Answers,
    us.TotalScore,
    COALESCE(bs.GoldBadges, 0)   AS GoldBadges,
    COALESCE(bs.SilverBadges, 0) AS SilverBadges,
    COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(bs.TotalBadges, 0)  AS TotalBadges,
    ur.RecentActivity,
    CAST(NULL AS bigint),
    CAST(NULL AS text),
    CAST(NULL AS text)
FROM UserStats us
LEFT JOIN BadgeStats bs       ON bs.UserId = us.Id
LEFT JOIN UserRecentActivity ur ON ur.Id = us.Id
WHERE us.Reputation < 2000
ORDER BY ScoreRank NULLS LAST, Id;