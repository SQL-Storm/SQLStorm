WITH
    UserStats AS (
        SELECT
            u.Id                                 AS UserId,
            u.DisplayName,
            u.Reputation,
            COALESCE(u.CreationDate, CAST('1970-01-01' AS timestamp))   AS UserSince,
            COALESCE(u.LastAccessDate, CAST('1970-01-01' AS timestamp)) AS LastSeen,
            COUNT(b.Id)                          AS TotalBadges,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    ),

    PostAgg AS (
        SELECT
            p.OwnerUserId                      AS UserId,
            COUNT(*)                           AS TotalPosts,
            COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS Questions,
            COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS Answers,
            AVG(COALESCE(p.Score,0))           AS AvgScore,
            MAX(p.LastActivityDate)            AS LastPostActivity,
            STRING_AGG(
                DISTINCT CASE
                    WHEN p.Tags IS NULL THEN NULL
                    ELSE TRIM(BOTH '<>' FROM split_part(p.Tags, '><', 1))
                END,
                ';'
            ) FILTER (WHERE p.Tags IS NOT NULL) AS PrimaryTagList
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    RecentPosts AS (
        SELECT
            p.OwnerUserId                                    AS UserId,
            p.Id                                            AS PostId,
            p.Title,
            p.CreationDate,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                               ORDER BY p.CreationDate DESC) AS RecencyRank
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
          AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
    ),

    TagStats AS (
        SELECT
            t.TagName,
            t.Count                                         AS TagUseCount,
            ROW_NUMBER() OVER (ORDER BY t.Count DESC)      AS TagRank
        FROM Tags t
        WHERE t.TagName IS NOT NULL
    ),

    UsersWithoutPosts AS (
        SELECT
            u.Id               AS UserId,
            u.DisplayName,
            CAST(NULL AS int)          AS TotalPosts,
            CAST(NULL AS int)          AS Questions,
            CAST(NULL AS int)          AS Answers,
            CAST(NULL AS numeric)      AS AvgScore,
            CAST(NULL AS timestamp)    AS LastPostActivity,
            CAST(NULL AS text)         AS PrimaryTagList
        FROM Users u
        WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
    )

SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.TotalBadges,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    COALESCE(pa.TotalPosts, 0)                          AS TotalPosts,
    COALESCE(pa.Questions, 0)                           AS QuestionCount,
    COALESCE(pa.Answers, 0)                             AS AnswerCount,
    ROUND(CAST(COALESCE(pa.AvgScore, 0) AS numeric), 2)        AS AvgPostScore,
    GREATEST(us.LastSeen, COALESCE(pa.LastPostActivity, CAST('1970-01-01' AS timestamp))) AS LastActivity,
    EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - 
        GREATEST(us.LastSeen, COALESCE(pa.LastPostActivity, CAST('1970-01-01' AS timestamp))))) 
        AS DaysSinceLastActivity,
    pa.PrimaryTagList,
    (SELECT STRING_AGG(rp.Title, ' | ')
     FROM RecentPosts rp
     WHERE rp.UserId = us.UserId
       AND rp.RecencyRank <= 3)                         AS RecentTop3Titles,
    CASE 
        WHEN us.GoldBadges > 0 AND COALESCE(pa.AvgScore,0) > 5 THEN 'Elite'
        WHEN us.Reputation > 20000 THEN 'HighRep'
        ELSE 'Standard'
    END                                                AS UserTier,
    (us.Reputation * 0.6) +
    (us.TotalBadges * 15) +
    (COALESCE(pa.TotalPosts,0) * 2) +
    (COALESCE(us.GoldBadges,0) * 100) AS InfluenceScore
FROM UserStats us
LEFT JOIN PostAgg pa ON pa.UserId = us.UserId

UNION ALL

SELECT
    uwp.UserId,
    uwp.DisplayName,
    CAST(NULL AS int)          AS Reputation,
    0                  AS TotalBadges,
    0                  AS GoldBadges,
    0                  AS SilverBadges,
    0                  AS BronzeBadges,
    0                  AS TotalPosts,
    0                  AS QuestionCount,
    0                  AS AnswerCount,
    0                  AS AvgPostScore,
    CAST(NULL AS timestamp)    AS LastActivity,
    CAST(NULL AS int)          AS DaysSinceLastActivity,
    CAST(NULL AS text)         AS PrimaryTagList,
    CAST(NULL AS text)         AS RecentTop3Titles,
    'Inactive'         AS UserTier,
    0                  AS InfluenceScore
FROM UsersWithoutPosts uwp
ORDER BY InfluenceScore DESC NULLS LAST
LIMIT 200;