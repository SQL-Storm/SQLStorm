WITH 
UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)      AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2)      AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3)      AS BronzeBadges,
        COALESCE(SUM(p.Score),0)                    AS TotalPostScore,
        COUNT(p.Id)                                 AS PostCount,
        MAX(p.CreationDate)                        AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b  ON b.UserId = u.Id
    LEFT JOIN Posts  p  ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count                           AS TagUseCount,
        COALESCE(SUM(p.Score),0)          AS TagScore,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    LEFT JOIN Posts p 
        ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    GROUP BY t.TagName, t.Count
),
RecentVotes AS (
    SELECT 
        v.UserId,
        COUNT(*) AS VoteCount30d
    FROM Votes v
    WHERE v.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
    GROUP BY v.UserId
),
TopUsers AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.TotalPostScore,
        us.PostCount,
        us.LastPostDate,
        RANK() OVER (ORDER BY us.Reputation DESC) AS RepRank
    FROM UserStats us
    ORDER BY us.Reputation DESC
    LIMIT 100
)
SELECT 
    tu.Id                              AS UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.TotalPostScore,
    tu.PostCount,
    tu.LastPostDate,
    COALESCE(rv.VoteCount30d,0)        AS RecentVoteCount,
    t.TagName,
    t.TagUseCount,
    t.TagScore,
    t.TagRank
FROM TopUsers tu
LEFT JOIN RecentVotes rv 
    ON rv.UserId = tu.Id
LEFT JOIN LATERAL (
        SELECT 
            ts.TagName,
            ts.TagUseCount,
            ts.TagScore,
            ts.TagRank
        FROM TagStats ts
        WHERE ts.TagRank <= 5
        ORDER BY ts.TagScore DESC
        LIMIT 1
    ) t ON TRUE
WHERE tu.LastPostDate IS NOT NULL 
   OR tu.PostCount = 0

UNION ALL

SELECT 
    NULL                               AS UserId,
    'Aggregate'                        AS DisplayName,
    NULL                               AS Reputation,
    SUM(GoldBadges)                    AS GoldBadges,
    SUM(SilverBadges)                  AS SilverBadges,
    SUM(BronzeBadges)                  AS BronzeBadges,
    SUM(TotalPostScore)                AS TotalPostScore,
    SUM(PostCount)                     AS PostCount,
    NULL                               AS LastPostDate,
    SUM(RecentVoteCount)               AS RecentVoteCount,
    NULL                               AS TagName,
    NULL                               AS TagUseCount,
    NULL                               AS TagScore,
    NULL                               AS TagRank
FROM (
    SELECT 
        tu.Id,
        tu.GoldBadges,
        tu.SilverBadges,
        tu.BronzeBadges,
        tu.TotalPostScore,
        tu.PostCount,
        COALESCE(rv.VoteCount30d,0) AS RecentVoteCount
    FROM TopUsers tu
    LEFT JOIN RecentVotes rv 
        ON rv.UserId = tu.Id
) agg;