WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id)                                 AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COALESCE(SUM(p.Score),0)                             AS SumScore,
        COALESCE(AVG(p.Score),0)                             AS AvgScore,
        MAX(p.CreationDate)                                 AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

BadgeAgg AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)        AS GoldCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)        AS SilverCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)        AS BronzeCount,
        -- Use a portable aggregation for concatenation; many DBs support LISTAGG or GROUP_CONCAT
        -- Here we use STRING_AGG for DBs that support it; if unsupported, swap to appropriate function.
        STRING_AGG(DISTINCT b.Name, ', ')                  AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),

RecentVotes AS (
    SELECT 
        v.PostId,
        MAX(v.CreationDate)                                 AS LastVoteDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)   AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)   AS DownVotes
    FROM Votes v
    WHERE v.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY)
    GROUP BY v.PostId
),

TagUsage AS (
    SELECT 
        t.TagName,
        COUNT(p.Id)                                         AS TaggedPosts,
        AVG(p.Score)                                        AS AvgTagScore
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName
),

UserRank AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.TotalPosts,
        us.Questions,
        us.Answers,
        us.SumScore,
        us.AvgScore,
        us.LastPostDate,
        ba.GoldCount,
        ba.SilverCount,
        ba.BronzeCount,
        ba.BadgeNames,
        ROW_NUMBER()   OVER (ORDER BY us.Reputation DESC, us.SumScore DESC) AS ReputationRank,
        DENSE_RANK()   OVER (ORDER BY us.AvgScore DESC)                     AS AvgScoreRank
    FROM UserStats us
    LEFT JOIN BadgeAgg ba ON ba.UserId = us.Id
)

SELECT 
    ur.Id,
    COALESCE(ur.DisplayName,'Anonymous')                AS DisplayName,
    ur.Reputation,
    ur.TotalPosts,
    ur.Questions,
    ur.Answers,
    ur.SumScore,
    ROUND(CAST(ur.AvgScore AS NUMERIC),2)               AS AvgScore,
    ur.LastPostDate,
    ur.GoldCount,
    ur.SilverCount,
    ur.BronzeCount,
    ur.BadgeNames,
    ur.ReputationRank,
    ur.AvgScoreRank,
    CASE
        WHEN ur.ReputationRank <= 10  THEN 'Top 10'
        WHEN ur.ReputationRank <= 100 THEN 'Top 100'
        ELSE 'Other'
    END                                                AS RankTier,
    (SELECT COUNT(*) 
     FROM Posts p 
     WHERE p.OwnerUserId = ur.Id 
       AND p.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '7' DAY)) AS PostsLastWeek,
    (SELECT STRING_AGG(DISTINCT t.TagName, ', ')
     FROM Tags t 
     JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
     WHERE p.OwnerUserId = ur.Id)                     AS UsedTags,
    COALESCE(rv.UpVotes,0)                             AS RecentUpVotes,
    COALESCE(rv.DownVotes,0)                           AS RecentDownVotes,
    rv.LastVoteDate
FROM UserRank ur
LEFT JOIN RecentVotes rv 
       ON rv.PostId = (
           SELECT p.Id 
           FROM Posts p 
           WHERE p.OwnerUserId = ur.Id 
           ORDER BY p.CreationDate DESC 
           LIMIT 1
       )
WHERE ur.Reputation > 1000

UNION ALL

SELECT 
    -1                                                AS Id,
    'Aggregate Summary'                               AS DisplayName,
    NULL                                              AS Reputation,
    SUM(TotalPosts)                                   AS TotalPosts,
    SUM(Questions)                                    AS Questions,
    SUM(Answers)                                      AS Answers,
    SUM(SumScore)                                     AS SumScore,
    ROUND(AVG(CAST(AvgScore AS NUMERIC)),2)           AS AvgScore,
    MAX(LastPostDate)                                 AS LastPostDate,
    SUM(GoldCount)                                    AS GoldCount,
    SUM(SilverCount)                                  AS SilverCount,
    SUM(BronzeCount)                                  AS BronzeCount,
    NULL                                              AS BadgeNames,
    NULL                                              AS ReputationRank,
    NULL                                              AS AvgScoreRank,
    NULL                                              AS RankTier,
    NULL                                              AS PostsLastWeek,
    NULL                                              AS UsedTags,
    NULL                                              AS RecentUpVotes,
    NULL                                              AS RecentDownVotes,
    NULL                                              AS LastVoteDate
FROM UserRank
WHERE Reputation > 1000

ORDER BY ReputationRank NULLS LAST, Id;