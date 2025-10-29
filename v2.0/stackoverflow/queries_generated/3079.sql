-- {"query": "3079.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2160} 

WITH cte_user_posts AS (
    SELECT u.Id                                    AS UserId,
           u.DisplayName,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
           COALESCE(SUM(p.Score),0)                     AS TotalScore,
           MAX(p.CreationDate)                         AS LastPostDate
    FROM   Users u
    LEFT  JOIN Posts p
           ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
cte_user_badges AS (
    SELECT b.UserId,
           COUNT(*)                                               AS BadgeCount,
           COUNT(*) FILTER (WHERE b.Class = 1)                    AS GoldBadges,
           COUNT(*) FILTER (WHERE b.Class = 2)                    AS SilverBadges,
           COUNT(*) FILTER (WHERE b.Class = 3)                    AS BronzeBadges,
           STRING_AGG(DISTINCT b.Name, ',')                       AS BadgeNames
    FROM   Badges b
    GROUP BY b.UserId
),
cte_tag_usage AS (
    SELECT u.Id                                            AS UserId,
           UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag,
           COUNT(*)                                        AS TagUsage
    FROM   Users u
    JOIN   Posts p
           ON p.OwnerUserId = u.Id
          AND p.PostTypeId = 1
          AND p.Tags IS NOT NULL
    GROUP BY u.Id, Tag
),
cte_top_tags AS (
    SELECT tu.UserId,
           STRING_AGG(tu.Tag, ',' ORDER BY tu.TagUsage DESC, tu.Tag)
               FILTER (WHERE rn <= 5) AS Top5Tags
    FROM  (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagUsage DESC, Tag) AS rn
            FROM   cte_tag_usage
          ) tu
    GROUP BY tu.UserId
),
cte_recent_votes AS (
    SELECT v.PostId,
           MAX(v.CreationDate)                                   AS LastVoteDate,
           COUNT(*) FILTER (WHERE vt.Id = 2)                     AS UpVotes,
           COUNT(*) FILTER (WHERE vt.Id = 3)                     AS DownVotes
    FROM   Votes v
    JOIN   VoteTypes vt
           ON vt.Id = v.VoteTypeId
    WHERE  v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.PostId
),
final AS (
    SELECT up.UserId,
           up.DisplayName,
           up.QuestionCount,
           up.AnswerCount,
           up.TotalScore,
           up.LastPostDate,
           COALESCE(ub.BadgeCount,0)            AS BadgeCount,
           COALESCE(ub.GoldBadges,0)            AS GoldBadges,
           COALESCE(ub.SilverBadges,0)          AS SilverBadges,
           COALESCE(ub.BronzeBadges,0)          AS BronzeBadges,
           ub.BadgeNames,
           tt.Top5Tags,
           (SELECT AVG(p2.Score)::numeric(10,2)
              FROM Posts p2
             WHERE p2.OwnerUserId = up.UserId
               AND p2.PostTypeId = 2)           AS AvgAnswerScore,
           ROW_NUMBER() OVER (ORDER BY up.TotalScore DESC NULLS LAST) AS RankByScore
    FROM   cte_user_posts up
    LEFT   JOIN cte_user_badges ub ON ub.UserId = up.UserId
    LEFT   JOIN cte_top_tags   tt ON tt.UserId = up.UserId
)
SELECT *
FROM   final
WHERE  (QuestionCount + AnswerCount) > 0
  AND (BadgeCount IS NULL OR BadgeCount >= 0)
  AND (RankByScore <= 1000 OR RankByScore IS NULL)

UNION ALL

SELECT
       -1                                          AS UserId,
       'Community'                                 AS DisplayName,
       SUM(QuestionCount)                          AS QuestionCount,
       SUM(AnswerCount)                            AS AnswerCount,
       SUM(TotalScore)                             AS TotalScore,
       MAX(LastPostDate)                           AS LastPostDate,
       SUM(BadgeCount)                             AS BadgeCount,
       SUM(GoldBadges)                             AS GoldBadges,
       SUM(SilverBadges)                           AS SilverBadges,
       SUM(BronzeBadges)                           AS BronzeBadges,
       STRING_AGG(DISTINCT BadgeNames, ',')        AS BadgeNames,
       STRING_AGG(DISTINCT Top5Tags, ',')          AS Top5Tags,
       NULL::numeric(10,2)                         AS AvgAnswerScore,
       NULL::int                                   AS RankByScore
FROM   final
WHERE  UserId <> -1
HAVING COUNT(*) > 0
ORDER BY TotalScore DESC NULLS LAST
LIMIT 500;
