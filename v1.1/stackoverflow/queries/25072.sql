WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)                                     AS QuestionCount,
           COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)                                     AS AnswerCount,
           AVG(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score END)                            AS AvgScore,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)                                 AS UpVoteGiven,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)                                 AS DownVoteGiven,
           COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 8 THEN ph.Id END)                 AS BountiesStarted
    FROM   Users u
    LEFT JOIN Posts p          ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v          ON v.UserId = u.Id
    LEFT JOIN PostHistory ph   ON ph.PostHistoryTypeId = 8 AND ph.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeCounts AS (
    SELECT b.UserId,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM   Badges b
    GROUP BY b.UserId
),
TagUsage AS (
    SELECT us.Id                               AS UserId,
           t.tag                               AS Tag,
           COUNT(*)                            AS TagCount
    FROM   UserStats us
    JOIN   Posts p        ON p.OwnerUserId = us.Id AND p.PostTypeId = 1
    CROSS JOIN LATERAL (
        -- split tags like '<tag1><tag2>' into rows; use standard SQL approach where available
        SELECT regexp_split_to_table(p.Tags, '\><') AS tag
    ) AS t
    GROUP BY us.Id, t.tag
),
TopTags AS (
    SELECT tu.UserId,
           STRING_AGG(tu.Tag || ':' || CAST(tu.TagCount AS varchar), ', ') AS TopTagList
    FROM   (
             SELECT t.*,
                    ROW_NUMBER() OVER (PARTITION BY t.UserId ORDER BY t.TagCount DESC) AS rn
             FROM   TagUsage t
           ) tu
    WHERE  tu.rn <= 5
    GROUP BY tu.UserId
),
MainRows AS (
SELECT us.Id,
       us.DisplayName,
       us.Reputation,
       RANK() OVER (ORDER BY us.Reputation DESC)                           AS ReputationRank,
       us.QuestionCount,
       us.AnswerCount,
       COALESCE(us.AvgScore,0)                                             AS AvgPostScore,
       COALESCE(bc.GoldBadges,0)                                            AS GoldBadges,
       COALESCE(bc.SilverBadges,0)                                          AS SilverBadges,
       COALESCE(bc.BronzeBadges,0)                                          AS BronzeBadges,
       COALESCE(tt.TopTagList,'')                                          AS TopTags,
       (SELECT COUNT(*)
        FROM   Posts p2
        WHERE  p2.OwnerUserId = us.Id
               AND p2.PostTypeId = 1
               AND p2.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '30' DAY))   AS RecentQuestions30d,
       (SELECT COUNT(*)
        FROM   Posts a
        WHERE  a.OwnerUserId = us.Id
               AND a.PostTypeId = 2
               AND a.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '30' DAY))   AS RecentAnswers30d,
       CASE WHEN us.Reputation IS NULL THEN 'UNKNOWN' ELSE 'KNOWN' END    AS RepStatus,
       (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.UserId = us.Id)  AS LastVoteDate
FROM   UserStats us
LEFT JOIN BadgeCounts bc ON bc.UserId = us.Id
LEFT JOIN TopTags tt    ON tt.UserId = us.Id
WHERE  us.Reputation > (
           SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Reputation)
           FROM   Users
       )
)
SELECT *
FROM (
  SELECT Id,
         DisplayName,
         Reputation,
         ReputationRank,
         QuestionCount,
         AnswerCount,
         AvgPostScore,
         GoldBadges,
         SilverBadges,
         BronzeBadges,
         TopTags,
         RecentQuestions30d,
         RecentAnswers30d,
         RepStatus,
         LastVoteDate
  FROM MainRows

  UNION ALL

  SELECT CAST(NULL AS BIGINT)       AS Id,
         CAST('---' AS VARCHAR)     AS DisplayName,
         CAST(NULL AS NUMERIC)      AS Reputation,
         CAST(NULL AS BIGINT)       AS ReputationRank,
         CAST(NULL AS BIGINT)       AS QuestionCount,
         CAST(NULL AS BIGINT)       AS AnswerCount,
         CAST(NULL AS NUMERIC)     AS AvgPostScore,
         CAST(NULL AS BIGINT)      AS GoldBadges,
         CAST(NULL AS BIGINT)      AS SilverBadges,
         CAST(NULL AS BIGINT)      AS BronzeBadges,
         CAST(NULL AS VARCHAR)     AS TopTags,
         CAST(NULL AS BIGINT)      AS RecentQuestions30d,
         CAST(NULL AS BIGINT)      AS RecentAnswers30d,
         CAST(NULL AS VARCHAR)     AS RepStatus,
         CAST(NULL AS TIMESTAMP)   AS LastVoteDate
) t
ORDER BY ReputationRank NULLS LAST
FETCH FIRST 10 ROWS ONLY;