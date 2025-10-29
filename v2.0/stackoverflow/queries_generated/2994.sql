-- {"query": "2994.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1333} 
WITH RecursiveCte AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.Title,
    COALESCE(p.Tags, '') AS Tags,
    u.Reputation,
    u.DisplayName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= NOW() - INTERVAL '5 years'
  
  UNION ALL
  
  SELECT
    p2.Id,
    p2.PostTypeId,
    p2.OwnerUserId,
    p2.Score,
    p2.ViewCount,
    p2.CreationDate,
    p2.Title,
    COALESCE(p2.Tags, '') AS Tags,
    u2.Reputation,
    u2.DisplayName,
    cte.rn + 1
  FROM Posts p2
  INNER JOIN RecursiveCte cte ON p2.ParentId = cte.Id
  LEFT JOIN Users u2 ON p2.OwnerUserId = u2.Id
  WHERE cte.rn < 3
),
UserBadgeCounts AS (
  SELECT
    b.UserId,
    b.Class,
    COUNT(*) AS BadgeCount
  FROM Badges b
  GROUP BY b.UserId, b.Class
),
UserVoteCounts AS (
  SELECT
    v.UserId,
    COUNT(*) FILTER (WHERE vt.Name = 'UpMod') AS UpVotesCount,
    COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotesCount
  FROM Votes v
  INNER JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE v.UserId IS NOT NULL
  GROUP BY v.UserId
),
PostScoreRank AS (
  SELECT
    p.Id,
    p.OwnerUserId,
    p.Score,
    RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS ScoreRank
  FROM Posts p
  WHERE p.PostTypeId = 2
),
CloseHistory AS (
  SELECT
    ph.PostId,
    MAX(ph.CreationDate) AS LastCloseDate,
    COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseCount,
    COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 END) AS ReopenCount
  FROM PostHistory ph
  GROUP BY ph.PostId
),
QuestionDuplicates AS (
  SELECT DISTINCT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Name = 'Duplicate'
),
QuestionsWithAnswers AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    COUNT(a.Id) AS AnswerCount,
    AVG(a.Score) AS AvgAnswerScore,
    MAX(a.Score) AS MaxAnswerScore,
    STRING_AGG(DISTINCT t.TagName, ',' ORDER BY t.TagName) AS TagsList
  FROM Posts q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><'))::text AS TagName
  ) t ON TRUE
  WHERE q.PostTypeId = 1
  GROUP BY q.Id, q.Title, q.CreationDate, q.ViewCount
)
SELECT
  qc.QuestionId,
  qc.Title,
  qc.CreationDate,
  qc.ViewCount,
  qc.AnswerCount,
  qc.AvgAnswerScore,
  qc.MaxAnswerScore,
  qc.TagsList,
  dh.LastCloseDate,
  dh.CloseCount,
  dh.ReopenCount,
  uba.UpVotesCount,
  uba.DownVotesCount,
  ubc_badge.GoldBadges,
  ubc_badge.SilverBadges,
  ubc_badge.BronzeBadges,
  usr.DisplayName AS OwnerDisplayName,
  usr.Reputation,
  STRING_AGG(DISTINCT CASE WHEN qd.RelatedPostId IS NOT NULL THEN 'Dup:'+ qd.RelatedPostId::text ELSE NULL END, ',') AS DuplicateQuestionIds,
  ROW_NUMBER() OVER (ORDER BY qc.ViewCount DESC, qc.AnswerCount DESC) AS PopularityRank
FROM QuestionsWithAnswers qc
LEFT JOIN CloseHistory dh ON qc.QuestionId = dh.PostId
LEFT JOIN UserVoteCounts uba ON uba.UserId = (
  SELECT OwnerUserId FROM Posts WHERE Id = qc.QuestionId
)
LEFT JOIN (
  SELECT
    UserId,
    MAX(CASE WHEN Class = 1 THEN BadgeCount ELSE 0 END) AS GoldBadges,
    MAX(CASE WHEN Class = 2 THEN BadgeCount ELSE 0 END) AS SilverBadges,
    MAX(CASE WHEN Class = 3 THEN BadgeCount ELSE 0 END) AS BronzeBadges
  FROM UserBadgeCounts
  GROUP BY UserId
) ubc_badge ON ubc_badge.UserId = (
  SELECT OwnerUserId FROM Posts WHERE Id = qc.QuestionId
)
LEFT JOIN Users usr ON usr.Id = (
  SELECT OwnerUserId FROM Posts WHERE Id = qc.QuestionId
)
LEFT JOIN QuestionDuplicates qd ON qd.PostId = qc.QuestionId
GROUP BY
  qc.QuestionId,
  qc.Title,
  qc.CreationDate,
  qc.ViewCount,
  qc.AnswerCount,
  qc.AvgAnswerScore,
  qc.MaxAnswerScore,
  qc.TagsList,
  dh.LastCloseDate,
  dh.CloseCount,
  dh.ReopenCount,
  uba.UpVotesCount,
  uba.DownVotesCount,
  ubc_badge.GoldBadges,
  ubc_badge.SilverBadges,
  ubc_badge.BronzeBadges,
  usr.DisplayName,
  usr.Reputation
HAVING qc.ViewCount > 1000
   AND (dh.CloseCount IS NULL OR dh.CloseCount < 3)
ORDER BY PopularityRank
LIMIT 50;