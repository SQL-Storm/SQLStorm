WITH 
    /* Aggregate posts per user */
    PostAgg AS (
        SELECT 
            p.OwnerUserId                                    AS UserId,
            COUNT(*)                                         AS TotalPosts,
            SUM(p.Score)                                    AS SumScore,
            AVG(p.Score)                                    AS AvgScore,
            MAX(p.CreationDate)                             AS LastPostDate,
            MIN(p.CreationDate)                             AS FirstPostDate
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    /* Aggregate badges per user */
    BadgeAgg AS (
        SELECT 
            b.UserId,
            COUNT(*)                                            AS TotalBadges,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)       AS Gold,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)       AS Silver,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)       AS Bronze
        FROM Badges b
        GROUP BY b.UserId
    ),
    /* Latest vote per user using a window function */
    LatestVote AS (
        SELECT 
            v.UserId,
            v.PostId,
            vt.Name                                              AS VoteType,
            v.CreationDate,
            ROW_NUMBER() OVER (PARTITION BY v.UserId 
                               ORDER BY v.CreationDate DESC)   AS rn
        FROM Votes v
        JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
        WHERE v.UserId IS NOT NULL
    ),
    TopVote AS (
        SELECT 
            lv.UserId,
            lv.PostId,
            lv.VoteType,
            lv.CreationDate
        FROM LatestVote lv
        WHERE lv.rn = 1
    ),
    /* Users enriched with correlated sub-queries and string ops */
    UserEnriched AS (
        SELECT 
            u.Id                                               AS UserId,
            COALESCE(u.DisplayName, 'Anonymous')               AS DisplayName,
            u.Reputation,
            u.CreationDate,
            /* correlated count of comments authored by the user */
            (SELECT COUNT(*) 
               FROM Comments c 
               WHERE c.UserId = u.Id)                         AS CommentCount,
            /* string key built from ID and name */
            CONCAT('U_', CAST(u.Id AS varchar), '_', 
                   REPLACE(COALESCE(u.DisplayName, ''), ' ', '_')) AS UserKey
        FROM Users u
    ),

    /* Full outer join to capture users with/without activity */
    FullUserStats AS (
        SELECT 
            ue.UserId,
            ue.DisplayName,
            ue.Reputation,
            ue.CreationDate,
            ue.CommentCount,
            ue.UserKey,
            COALESCE(pa.TotalPosts, 0)                         AS TotalPosts,
            COALESCE(pa.SumScore, 0)                           AS SumScore,
            COALESCE(pa.AvgScore, 0)                           AS AvgScore,
            pa.LastPostDate                                    AS LastPostDate,
            COALESCE(ba.TotalBadges, 0)                        AS TotalBadges,
            COALESCE(ba.Gold, 0)                               AS GoldBadges,
            COALESCE(ba.Silver, 0)                             AS SilverBadges,
            COALESCE(ba.Bronze, 0)                             AS BronzeBadges,
            tv.VoteType,
            tv.CreationDate                                    AS LastVoteDate
        FROM UserEnriched ue
        FULL OUTER JOIN PostAgg pa   ON ue.UserId = pa.UserId
        FULL OUTER JOIN BadgeAgg ba  ON ue.UserId = ba.UserId
        LEFT JOIN TopVote tv          ON ue.UserId = tv.UserId
    ),

    /* Dummy row representing "no user" for set-operator demonstration */
    NoUserRow AS (
        SELECT 
            CAST(NULL AS INTEGER)           AS UserId,
            'NoUser'                         AS DisplayName,
            0                                AS Reputation,
            CAST(NULL AS TIMESTAMP)          AS CreationDate,
            0                                AS CommentCount,
            'U_NULL'                         AS UserKey,
            0                                AS TotalPosts,
            0                                AS SumScore,
            0                                AS AvgScore,
            CAST(NULL AS TIMESTAMP)          AS LastPostDate,
            0                                AS TotalBadges,
            0                                AS GoldBadges,
            0                                AS SilverBadges,
            0                                AS BronzeBadges,
            CAST(NULL AS VARCHAR(50))        AS VoteType,
            CAST(NULL AS TIMESTAMP)          AS LastVoteDate
    )

SELECT 
    fus.UserId,
    fus.DisplayName,
    fus.Reputation,
    fus.CreationDate,
    fus.CommentCount,
    fus.UserKey,
    fus.TotalPosts,
    fus.SumScore,
    fus.AvgScore,
    fus.LastPostDate,
    fus.TotalBadges,
    fus.GoldBadges,
    fus.SilverBadges,
    fus.BronzeBadges,
    fus.VoteType,
    fus.LastVoteDate
FROM FullUserStats fus
WHERE 
      fus.Reputation >= 1000
   OR (fus.LastPostDate IS NOT NULL 
       AND fus.LastPostDate >= TIMESTAMP '2020-01-01')
   OR (fus.TotalPosts > 0 AND fus.CommentCount IS NULL)
UNION ALL
SELECT 
    nu.UserId,
    nu.DisplayName,
    nu.Reputation,
    nu.CreationDate,
    nu.CommentCount,
    nu.UserKey,
    nu.TotalPosts,
    nu.SumScore,
    nu.AvgScore,
    nu.LastPostDate,
    nu.TotalBadges,
    nu.GoldBadges,
    nu.SilverBadges,
    nu.BronzeBadges,
    nu.VoteType,
    nu.LastVoteDate
FROM NoUserRow nu
ORDER BY 
      Reputation DESC,
      TotalPosts DESC,
      UserId ASC
LIMIT 100;