WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(SUM(p.Score), 0)               AS TotalPostScore,
        COALESCE(SUM(p.ViewCount), 0)           AS TotalViews,
        COALESCE(COUNT(p.Id), 0)                AS PostCount,
        COALESCE(MIN(p.CreationDate), u.CreationDate) AS FirstPostDate
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
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
        p.OwnerUserId               AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        COUNT(DISTINCT v.UserId) FILTER (WHERE v.VoteTypeId = 5) AS FavoritesReceived
    FROM Posts p
    LEFT JOIN Votes v
        ON v.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

RecentTagActivity AS (
    SELECT 
        u.Id                                        AS UserId,
        STRING_AGG(DISTINCT trim(both '><' FROM t.TagName), ', ') AS RecentTags
    FROM Users u
    JOIN Posts p
        ON p.OwnerUserId = u.Id
    JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS Tag
    ) AS taglist ON true
    JOIN Tags t
        ON t.TagName = taglist.Tag
    WHERE p.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '90 days')
    GROUP BY u.Id
),

Combined AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.TotalPostScore,
        us.TotalViews,
        us.PostCount,
        us.FirstPostDate,
        COALESCE(bs.GoldBadges,   0) AS GoldBadges,
        COALESCE(bs.SilverBadges, 0) AS SilverBadges,
        COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(bs.TotalBadges,  0) AS TotalBadges,
        COALESCE(vs.UpVotesReceived,   0) AS UpVotesReceived,
        COALESCE(vs.DownVotesReceived, 0) AS DownVotesReceived,
        COALESCE(vs.FavoritesReceived,0) AS FavoritesReceived,
        COALESCE(rta.RecentTags, '')    AS RecentTags,
        (COALESCE(vs.UpVotesReceived,0) - COALESCE(vs.DownVotesReceived,0)) 
                                         AS NetVotesReceived,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.TotalPostScore DESC) AS ReputationRank,
        PERCENT_RANK() OVER (ORDER BY us.TotalViews DESC)                         AS ViewPercentile
    FROM UserStats us
    LEFT JOIN BadgeStats bs   ON bs.UserId   = us.Id
    LEFT JOIN VoteStats vs    ON vs.UserId   = us.Id
    LEFT JOIN RecentTagActivity rta ON rta.UserId = us.Id
    WHERE us.Reputation > 1000
      AND (us.TotalPostScore + COALESCE(bs.TotalBadges,0) * 10) > 500
      AND (
            us.CreationDate < CAST('2024-10-01' AS date) - INTERVAL '1 year'
            OR us.LastAccessDate > CAST('2024-10-01' AS date) - INTERVAL '30 days'
          )
)

SELECT *
FROM Combined
ORDER BY ReputationRank
LIMIT 100;