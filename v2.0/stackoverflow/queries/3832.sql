WITH BadgeAgg AS (
    SELECT u.Id                           AS UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
           COUNT(b.Id)                                     AS TotalBadges
    FROM   Users u
    LEFT   JOIN Badges b ON b.UserId = u.Id
    GROUP  BY u.Id
),
PostAgg AS (
    SELECT u.Id                                                   AS UserId,
           COUNT(p.Id)                                            AS TotalPosts,
           SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END)     AS AnswerCount,
           SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END)     AS QuestionCount,
           SUM(CASE WHEN p.PostTypeId = 2 AND p.Id = p.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswers,
           AVG(p.Score) AS AvgScore,
           MAX(p.CreationDate)                                   AS LastPostDate,
           tags.AllTags                                          AS AllTags
    FROM   Users u
    LEFT   JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT   JOIN LATERAL (
      SELECT STRING_AGG(DISTINCT TRIM(BOTH '<>' FROM t.tag), ',') AS AllTags
      FROM (
        SELECT UNNEST(string_to_array(COALESCE(p.Tags, ''), '><')) AS tag
      ) t
      WHERE COALESCE(p.Tags, '') <> ''
    ) tags ON TRUE
    GROUP  BY u.Id, tags.AllTags
),
RecentActivity AS (
    SELECT u.Id                                                       AS UserId,
           GREATEST(COALESCE(MAX(v.CreationDate), TIMESTAMP '1970-01-01'),
                    COALESCE(MAX(c.CreationDate), TIMESTAMP '1970-01-01')) AS LastActivity
    FROM   Users u
    LEFT   JOIN Votes v   ON v.UserId = u.Id
    LEFT   JOIN Comments c ON c.UserId = u.Id
    GROUP  BY u.Id
),
UserMetrics AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(b.GoldBadges, 0)   AS GoldBadges,
           COALESCE(b.SilverBadges, 0) AS SilverBadges,
           COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
           COALESCE(p.TotalPosts, 0)   AS TotalPosts,
           COALESCE(p.AnswerCount, 0)  AS AnswerCount,
           COALESCE(p.QuestionCount, 0) AS QuestionCount,
           COALESCE(p.AcceptedAnswers, 0) AS AcceptedAnswers,
           CASE WHEN COALESCE(p.AnswerCount,0)=0 THEN NULL
                ELSE ROUND(100.0 * COALESCE(p.AcceptedAnswers,0) /
                           NULLIF(p.AnswerCount,0), 2)
           END                         AS AcceptanceRatePct,
           COALESCE(p.AvgScore,0)      AS AvgPostScore,
           COALESCE(r.LastActivity, u.CreationDate) AS LastActivityDate,
           COALESCE(p.AllTags,'')      AS TagList,
           (u.Reputation * 0.4
            + COALESCE(b.TotalBadges,0) * 10
            + COALESCE(p.TotalPosts,0) * 2
            + COALESCE(p.AcceptedAnswers,0) * 5) AS CompositeScore
    FROM   Users u
    LEFT   JOIN BadgeAgg b      ON b.UserId = u.Id
    LEFT   JOIN PostAgg p       ON p.UserId = u.Id
    LEFT   JOIN RecentActivity r ON r.UserId = u.Id
),
RankedUsers AS (
    SELECT um.Id,
           um.DisplayName,
           um.Reputation,
           um.GoldBadges,
           um.SilverBadges,
           um.BronzeBadges,
           um.TotalPosts,
           um.AnswerCount,
           um.QuestionCount,
           um.AcceptedAnswers,
           um.AcceptanceRatePct,
           um.AvgPostScore,
           um.LastActivityDate,
           um.TagList,
           um.CompositeScore,
           ROW_NUMBER() OVER (ORDER BY um.CompositeScore DESC) AS RankByScore,
           RANK()      OVER (ORDER BY um.Reputation DESC)    AS RankByReputation
    FROM   UserMetrics um
)
SELECT
    ru.Id,
    ru.DisplayName,
    ru.Reputation,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.TotalPosts,
    ru.AnswerCount,
    ru.QuestionCount,
    ru.AcceptedAnswers,
    ru.AcceptanceRatePct,
    ru.AvgPostScore,
    ru.LastActivityDate,
    CASE WHEN ru.TagList = '' THEN NULL ELSE ru.TagList END AS TopTags,
    ru.CompositeScore,
    ru.RankByScore,
    ru.RankByReputation
FROM   RankedUsers ru
WHERE  ru.RankByScore <= 100

UNION ALL

SELECT
    0 AS Id,
    'All Users Summary' AS DisplayName,
    SUM(ru.Reputation)           AS Reputation,
    SUM(ru.GoldBadges)           AS GoldBadges,
    SUM(ru.SilverBadges)         AS SilverBadges,
    SUM(ru.BronzeBadges)         AS BronzeBadges,
    SUM(ru.TotalPosts)           AS TotalPosts,
    SUM(ru.AnswerCount)          AS AnswerCount,
    SUM(ru.QuestionCount)        AS QuestionCount,
    SUM(ru.AcceptedAnswers)      AS AcceptedAnswers,
    NULL                         AS AcceptanceRatePct,
    AVG(ru.AvgPostScore)         AS AvgPostScore,
    MAX(ru.LastActivityDate)     AS LastActivityDate,
    NULL                         AS TopTags,
    NULL                         AS CompositeScore,
    NULL                         AS RankByScore,
    NULL                         AS RankByReputation
FROM   RankedUsers ru
ORDER BY CompositeScore DESC NULLS LAST
LIMIT 101;