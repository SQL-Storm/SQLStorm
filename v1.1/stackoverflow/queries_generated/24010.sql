-- {"query": "24010.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2191} 

WITH
/* Recent 30‑day questions */
RecentQuestions AS (
  SELECT p.Id            AS QuestionId,
         p.Title,
         p.Tags,
         p.OwnerUserId,
         p.CreationDate,
         p.AnswerCount,
         p.Score,
         p.ViewCount,
         p.LastActivityDate
  FROM   Posts p
  WHERE  p.PostTypeId = 1
  AND    p.CreationDate >= now() - interval '30 days'
),
/* Additional older questions to pad the result set */
OldQuestions AS (
  SELECT p.Id            AS QuestionId,
         p.Title,
         p.Tags,
         p.OwnerUserId,
         p.CreationDate,
         p.AnswerCount,
         p.Score,
         p.ViewCount,
         p.LastActivityDate
  FROM   Posts p
  WHERE  p.PostTypeId = 1
  AND    p.CreationDate BETWEEN now() - interval '90 days' AND now() - interval '30 days'
  LIMIT  20                                     /* limit added to keep row count reasonable */
),
/* Combine recent and older questions for ranking */
CombinedQuestions AS (
  SELECT * FROM RecentQuestions
  UNION ALL
  SELECT * FROM OldQuestions
),
/* Split tags from the XML‑style tag string */
TagSplit AS (
  SELECT q.QuestionId,
         unnest(
           string_to_array(
             substring(q.Tags, 2, length(q.Tags) - 2),  -- strip leading < and trailing >
             '><'
           )
         ) AS Tag
  FROM   CombinedQuestions q
),
/* Tag popularity among the questions returned */
TagStats AS (
  SELECT Tag,
         count(*) AS QuestionCount
  FROM   TagSplit
  GROUP  BY Tag
),
/* Badge counts per user */
UserBadges AS (
  SELECT u.Id               AS UserId,
         COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldCount,
         COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverCount,
         COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeCount
  FROM   Users u
  LEFT   JOIN Badges b ON b.UserId = u.Id
  GROUP  BY u.Id
),
/* Duplicate post links */
DuplicateLinks AS (
  SELECT pl.PostId,
         COUNT(*) AS DuplicateCount
  FROM   PostLinks pl
  WHERE  pl.LinkTypeId = 3
  GROUP  BY pl.PostId
)
/* Main query */
SELECT
  qc.QuestionId,
  qc.Title,
  qc.Tags,
  u.DisplayName,
  COALESCE(u.Reputation, 0)                               AS Reputation,
  COALESCE(ub.GoldCount, 0) + 
  COALESCE(ub.SilverCount, 0) + 
  COALESCE(ub.BronzeCount, 0)                            AS TotalBadgePoints,
  qc.AnswerCount,
  qc.Score,
  qc.ViewCount,
  qc.LastActivityDate,
  /* Correlated sub‑query: number of comments on this question */
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = qc.QuestionId) AS CommentCount,
  COALESCE(dl.DuplicateCount, 0)                         AS DuplicateLinks,
  /* Window function: rank by answer count, then score */
  ROW_NUMBER() OVER (ORDER BY qc.AnswerCount DESC, qc.Score DESC) AS RankByAnswers,
  /* Aggregate tags back into an array, filtering NULLs */
  array_agg(DISTINCT ts.Tag) FILTER (WHERE ts.Tag IS NOT NULL) AS TagArray,
  /* Complex predicate for activity stage */
  CASE 
    WHEN qc.LastActivityDate < qc.CreationDate + interval '7 days' THEN 'New'
    WHEN qc.AnswerCount > 5 AND qc.Score > 10 THEN 'Popular'
    ELSE 'Stable'
  END AS ActivityStage
FROM   CombinedQuestions qc
LEFT   JOIN Users u             ON u.Id = qc.OwnerUserId
LEFT   JOIN UserBadges ub        ON ub.UserId = qc.OwnerUserId
LEFT   JOIN DuplicateLinks dl    ON dl.PostId = qc.QuestionId
LEFT   JOIN TagSplit ts          ON ts.QuestionId = qc.QuestionId
GROUP  BY
  qc.QuestionId,
  qc.Title,
  qc.Tags,
  u.DisplayName,
  u.Reputation,
  ub.GoldCount, ub.SilverCount, ub.BronzeCount,
  qc.AnswerCount,
  qc.Score,
  qc.ViewCount,
  qc.LastActivityDate,
  dl.DuplicateCount,
  qc.CreationDate,
  qc.OwnerUserId,
  qc.PostId,                                 /* ensures consistent grouping */
  qc.CreationDate
ORDER BY RankByAnswers, qc.Score DESC
LIMIT 100;
