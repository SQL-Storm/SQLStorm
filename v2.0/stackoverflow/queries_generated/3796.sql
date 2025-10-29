-- {"query": "3796.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2593} 

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
    WHERE  p.PostTypeId = 1          -- Question
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
          AND a.PostTypeId = 2      -- Answer
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
                              ORDER BY ua.AvgScore DESC NULLS LAST,
                                       ua.Reputation DESC) AS RankInTag
    FROM   TopTags tt
    JOIN   BestAnswers ba
           ON ba.Tags IS NOT NULL
          AND EXISTS ( SELECT 1
                       FROM   regexp_split_to_table(ba.Tags, '><') AS tag_part
                       WHERE  '<' || tag_part || '>' = '<' || tt.TagName || '>' )
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
