WITH TopTags AS (
    SELECT t.Id   AS TagId,
           t.TagName,
           t.Count
    FROM   Tags t
    WHERE  t.Count > 5000
),

QuestionPosts AS (
    SELECT p.Id,
           p.OwnerUserId,
           p.Tags,
           p.CreationDate,
           p.Score
    FROM   Posts p
    WHERE  p.PostTypeId = 1
),

AnswerInfo AS (
    SELECT q.Id                 AS QuestionId,
           q.Tags,
           a.Id                 AS AnswerId,
           a.OwnerUserId        AS AnswererId,
           a.Score              AS AnswerScore,
           a.CreationDate       AS AnswerDate,
           ROW_NUMBER() OVER (PARTITION BY q.Id
                              ORDER BY a.Score DESC,
                                       a.CreationDate ASC) AS rn
    FROM   QuestionPosts q
    JOIN   Posts a
           ON a.ParentId = q.Id
          AND a.PostTypeId = 2
),

BestAnswers AS (
    SELECT *
    FROM   AnswerInfo
    WHERE  rn = 1
),

UserAggregates AS (
    SELECT u.Id   AS UserId,
           u.DisplayName,
           u.Reputation,
           COUNT(DISTINCT ba.QuestionId)               AS AnswerCount,
           AVG(ba.AnswerScore)                         AS AvgScore,
           COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END),0) AS GoldBadges,
           COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END),0) AS SilverBadges,
           COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END),0) AS BronzeBadges
    FROM   Users u
    LEFT   JOIN BestAnswers ba ON ba.AnswererId = u.Id
    LEFT   JOIN Badges b       ON b.UserId = u.Id
    GROUP  BY u.Id, u.DisplayName, u.Reputation
),

-- Since some SQL dialects do not provide regexp_split_to_table, emulate tag matching
-- by checking for substring patterns. Ensure Tags is not null before matching.
TagUserRank AS (
    SELECT tt.TagId,
           tt.TagName,
           ua.UserId,
           ua.DisplayName,
           ua.Reputation,
           ua.AnswerCount,
           ua.AvgScore,
           ua.GoldBadges,
           ua.SilverBadges,
           ua.BronzeBadges,
           ROW_NUMBER() OVER (PARTITION BY tt.TagId
                              ORDER BY ua.AvgScore DESC,
                                       ua.Reputation DESC) AS RankInTag
    FROM   TopTags tt
    JOIN   BestAnswers ba
           ON ba.Tags IS NOT NULL
          AND ('<' || tt.TagName || '>') IS NOT NULL
          AND POSITION(('<' || tt.TagName || '>') IN ba.Tags) > 0
    JOIN   UserAggregates ua
           ON ua.UserId = ba.AnswererId
)

SELECT
    tr.TagName,
    tr.RankInTag,
    tr.DisplayName,
    tr.Reputation,
    tr.AnswerCount,
    ROUND(tr.AvgScore,2) AS AvgScore,
    tr.GoldBadges,
    tr.SilverBadges,
    tr.BronzeBadges
FROM   TagUserRank tr
WHERE  tr.RankInTag <= 3

UNION ALL

SELECT
    'All Tags'       AS TagName,
    NULL             AS RankInTag,
    ua.DisplayName,
    ua.Reputation,
    ua.AnswerCount,
    ROUND(ua.AvgScore,2) AS AvgScore,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges
FROM   UserAggregates ua

ORDER BY TagName,
         RankInTag NULLS LAST,
         AvgScore DESC;