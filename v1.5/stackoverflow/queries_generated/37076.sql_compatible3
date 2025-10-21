WITH
Questions AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.OwnerUserId,
    p.Tags,
    regexp_split_to_table(substring(p.Tags, 2, length(p.Tags) - 2), E'><') AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2' YEAR)
),
TopQuestions AS (
  SELECT q.*
  FROM Questions q
  ORDER BY (q.Score * 4 + COALESCE(q.ViewCount, 0) / GREATEST(NULLIF(q.AnswerCount, 0), 1) + COALESCE(q.FavoriteCount, 0) * 10) DESC
  LIMIT 2000
),
AnswersAgg AS (
  SELECT
    a.ParentId AS QuestionId,
    COUNT(*) FILTER (WHERE a.Score >= 0) AS PositiveAnswers,
    COUNT(*) FILTER (WHERE a.Score < 0) AS NegativeAnswers,
    AVG(a.Score) AS AvgAnswerScore,
    MAX(a.Score) AS MaxAnswerScore,
    MIN(a.Score) AS MinAnswerScore,
    BOOL_OR(a.AcceptedAnswerId IS NOT NULL) AS HasAcceptedFlagPlaceholder
  FROM Posts a
  WHERE a.PostTypeId = 2
    AND a.ParentId IN (SELECT Id FROM TopQuestions)
  GROUP BY a.ParentId
),
CommentsAgg AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCountRecent,
    MAX(c.CreationDate) AS LastCommentDate,
    COUNT(*) FILTER (WHERE c.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)) AS Comments30d
  FROM Comments c
  WHERE c.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
    AND c.PostId IN (
      SELECT Id FROM TopQuestions
      UNION
      SELECT Id FROM Posts WHERE PostTypeId = 2 AND ParentId IN (SELECT Id FROM TopQuestions)
    )
  GROUP BY c.PostId
),
OwnerStats AS (
  SELECT
    u.Id AS OwnerUserId,
    u.Reputation,
    COUNT(b.Id) AS BadgeCount,
    COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - MIN(u.CreationDate))) / 86400 AS DaysSinceJoin
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE u.Id IN (SELECT DISTINCT OwnerUserId FROM TopQuestions WHERE OwnerUserId IS NOT NULL)
  GROUP BY u.Id, u.Reputation, u.CreationDate
),
LinkDensity AS (
  SELECT
    tl.PostId AS QuestionId,
    COUNT(*) FILTER (WHERE lt.Name = 'Linked') AS LinkedCount,
    COUNT(*) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicateCount,
    COUNT(*) AS TotalLinks
  FROM PostLinks tl
  JOIN LinkTypes lt ON lt.Id = tl.LinkTypeId
  WHERE tl.PostId IN (SELECT Id FROM TopQuestions)
  GROUP BY tl.PostId
),
VoteDist AS (
  SELECT
    v.PostId,
    COUNT(*) FILTER (WHERE vt.Name = 'UpMod') AS UpVotes,
    COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotes,
    COUNT(*) FILTER (WHERE vt.Name = 'Favorite') AS Favorites,
    COUNT(*) FILTER (WHERE vt.Name = 'AcceptedByOriginator') AS AcceptedByOwnerFlag,
    COUNT(*) AS TotalVotes
  FROM Votes v
  JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  WHERE v.PostId IN (SELECT Id FROM TopQuestions)
  GROUP BY v.PostId
),
QuestionMetrics AS (
  SELECT
    tq.Id AS QuestionId,
    tq.Title,
    tq.CreationDate,
    tq.Score AS QuestionScore,
    tq.ViewCount,
    tq.AnswerCount,
    tq.FavoriteCount,
    tq.Tags AS Tag,
    COALESCE(aa.PositiveAnswers, 0) AS PositiveAnswers,
    COALESCE(aa.NegativeAnswers, 0) AS NegativeAnswers,
    COALESCE(aa.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(ca.CommentCountRecent, 0) AS RecentComments,
    COALESCE(ca.Comments30d, 0) AS Comments30d,
    COALESCE(ld.LinkedCount, 0) AS LinkedCount,
    COALESCE(ld.DuplicateCount, 0) AS DuplicateCount,
    COALESCE(vd.UpVotes, 0) AS UpVotes,
    COALESCE(vd.DownVotes, 0) AS DownVotes,
    COALESCE(vd.TotalVotes, 0) AS TotalVotes,
    ow.Reputation AS OwnerReputation,
    ow.BadgeCount AS OwnerBadgeCount,
    ow.GoldBadges,
    ow.SilverBadges,
    ow.BronzeBadges,
    ow.DaysSinceJoin,
    ((tq.Score * 5)
      + GREATEST(LEAST(LOG(NULLIF(tq.ViewCount, 0) + 1), 50), 0) * 3
      + COALESCE(aa.AvgAnswerScore, 0) * 4
      + COALESCE(vd.UpVotes - vd.DownVotes, 0) * 2
      + COALESCE(tq.FavoriteCount, 0) * 10
      + COALESCE(ca.Comments30d, 0) * 6
      + (ow.Reputation * 1.0 / GREATEST(1, NULLIF(ow.DaysSinceJoin, 0))) * 0.5
      - COALESCE(ld.DuplicateCount, 0) * 8
    ) AS HotnessScore
  FROM TopQuestions tq
  LEFT JOIN AnswersAgg aa ON aa.QuestionId = tq.Id
  LEFT JOIN CommentsAgg ca ON ca.PostId = tq.Id
  LEFT JOIN LinkDensity ld ON ld.QuestionId = tq.Id
  LEFT JOIN VoteDist vd ON vd.PostId = tq.Id
  LEFT JOIN OwnerStats ow ON ow.OwnerUserId = tq.OwnerUserId
)
SELECT
  qm.QuestionId,
  qm.Title,
  qm.Tag,
  qm.CreationDate,
  qm.QuestionScore,
  qm.ViewCount,
  qm.AnswerCount,
  qm.PositiveAnswers,
  qm.NegativeAnswers,
  qm.AvgAnswerScore,
  qm.RecentComments,
  qm.Comments30d,
  qm.LinkedCount,
  qm.DuplicateCount,
  qm.UpVotes,
  qm.DownVotes,
  qm.TotalVotes,
  qm.OwnerReputation,
  qm.OwnerBadgeCount,
  qm.GoldBadges,
  qm.SilverBadges,
  qm.BronzeBadges,
  CAST(ROUND(qm.HotnessScore, 2) AS numeric) AS HotnessScore,
  RANK() OVER (PARTITION BY qm.Tag ORDER BY qm.HotnessScore DESC) AS TagHotRank,
  NTILE(100) OVER (ORDER BY qm.HotnessScore DESC) AS HotnessPercentile,
  CAST(ROUND(AVG(qm.HotnessScore) OVER (PARTITION BY qm.Tag ORDER BY qm.HotnessScore DESC ROWS BETWEEN 4 PRECEDING AND CURRENT ROW), 2) AS numeric) AS TagHot_MA_5,
  CAST(ROUND(STDDEV_SAMP(qm.HotnessScore) OVER (PARTITION BY qm.Tag), 2) AS numeric) AS TagHot_STDDEV
FROM QuestionMetrics qm
WHERE qm.HotnessScore IS NOT NULL
ORDER BY qm.HotnessScore DESC
LIMIT 500;