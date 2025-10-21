-- {"query": "39032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2912} 

WITH
RecentAnswers AS (
  SELECT
    p.ParentId       AS QuestionId,
    p.Id             AS AnswerId,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.CreationDate ASC) AS AnswerRank
  FROM Posts p
  WHERE p.PostTypeId = 2
),
QuestionStats AS (
  SELECT
    q.Id                                       AS QuestionId,
    q.OwnerUserId                             AS QuestionOwner,
    q.CreationDate                             AS QuestionDate,
    q.Score                                    AS QuestionScore,
    COUNT(DISTINCT c.Id)                       AS CommentCount,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
    COUNT(DISTINCT pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateCount,
    COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS EditCount
  FROM Posts q
  LEFT JOIN Comments    c  ON c.PostId     = q.Id
  LEFT JOIN Votes       v  ON v.PostId     = q.Id
  LEFT JOIN PostLinks   pl ON pl.PostId    = q.Id
  LEFT JOIN PostHistory ph ON ph.PostId    = q.Id
  WHERE q.PostTypeId = 1
  GROUP BY q.Id, q.OwnerUserId, q.CreationDate, q.Score
),
UserBadges AS (
  SELECT
    b.UserId,
    COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
  FROM Badges b
  GROUP BY b.UserId
),
TopTagUsage AS (
  SELECT
    u.Id            AS UserId,
    t.TagName,
    COUNT(*)        AS UsageCount,
    DENSE_RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS TagRank
  FROM Posts p
  CROSS JOIN LATERAL
       UNNEST(
         STRING_TO_ARRAY(
           SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2),
           '><'
         )
       ) AS t(TagName)
  JOIN Users u
    ON u.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1
  GROUP BY u.Id, t.TagName
)
SELECT
  qs.QuestionId,
  u.DisplayName      AS Author,
  qs.QuestionDate,
  qs.QuestionScore,
  qs.CommentCount,
  qs.UpVotes,
  qs.DownVotes,
  qs.DuplicateCount,
  qs.EditCount,
  ra.AnswerId,
  ra.CreationDate    AS FirstAnswerDate,
  EXTRACT(EPOCH FROM (ra.CreationDate - qs.QuestionDate)) / 3600 AS HoursToFirstAnswer,
  ub.GoldBadges,
  ub.SilverBadges,
  ub.BronzeBadges,
  tt.TagName         AS TopTag,
  tt.UsageCount      AS TopTagCount
FROM QuestionStats qs
JOIN RecentAnswers ra
  ON ra.QuestionId = qs.QuestionId
 AND ra.AnswerRank  = 1
JOIN Users u
  ON u.Id = qs.QuestionOwner
LEFT JOIN UserBadges ub
  ON ub.UserId = u.Id
LEFT JOIN TopTagUsage tt
  ON tt.UserId = u.Id
 AND tt.TagRank  = 1
ORDER BY qs.QuestionDate DESC
LIMIT 100;
