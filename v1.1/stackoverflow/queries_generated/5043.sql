-- {"query": "5043.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1198} 
WITH
TopActiveUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Location,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS rn
  FROM Users u
  WHERE u.DownVotes < u.UpVotes AND u.Reputation >= 1000
),
RecentQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.Tags,
    LOWER(SUBSTRING(p.Title, 1, 50)) AS TitlePrefix,
    COUNT(DISTINCT a.Id) OVER (PARTITION BY p.OwnerUserId) AS UserQuestionCount
  FROM Posts p
  LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
  WHERE p.PostTypeId = 1 AND p.CreationDate > NOW() - INTERVAL '90 days'
),
BadgeAgg AS (
  SELECT
    b.UserId,
    COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
    COUNT(*) AS TotalBadges,
    MAX(b.Date) AS LastBadgeDate
  FROM Badges b
  GROUP BY b.UserId
),
VoteStats AS (
  SELECT
    p.OwnerUserId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
    COUNT(v.Id) AS TotalVotesReceived
  FROM Posts p
  JOIN Votes v ON v.PostId = p.Id
  WHERE p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId
),
CommentLengths AS (
  SELECT
    c.UserId,
    AVG(LENGTH(c.Text)) AS AvgCommentLen,
    COUNT(*) AS CommentCount
  FROM Comments c
  WHERE c.UserId IS NOT NULL
  GROUP BY c.UserId
),
TagUsage AS (
  SELECT
    p.OwnerUserId,
    unnest(string_to_array(SUBSTRING(p.Tags, 2, length(p.Tags)-2), '><')) AS NormalizedTag
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
),
FrequentTags AS (
  SELECT
    OwnerUserId,
    NormalizedTag,
    COUNT(*) AS TagAppearances,
    RANK() OVER (PARTITION BY OwnerUserId ORDER BY COUNT(*) DESC, NormalizedTag) AS TagRank
  FROM TagUsage
  GROUP BY OwnerUserId, NormalizedTag
)
SELECT
  u.UserId,
  u.DisplayName,
  u.Reputation,
  u.Location,
  COALESCE(ba.GoldBadges,0) AS GoldBadges,
  COALESCE(ba.SilverBadges,0) AS SilverBadges,
  COALESCE(ba.BronzeBadges,0) AS BronzeBadges,
  COALESCE(ba.TotalBadges,0) AS TotalBadges,
  COALESCE(ba.LastBadgeDate, NULL) AS LastBadgeDate,
  vs.UpVotesReceived,
  vs.DownVotesReceived,
  vs.TotalVotesReceived,
  cl.AvgCommentLen,
  cl.CommentCount,
  COUNT(DISTINCT q.QuestionId) AS RecentQuestionsCount,
  MAX(q.Score) AS MaxRecentQuestionScore,
  MIN(q.ViewCount) AS MinRecentQuestionViews,
  ROUND(AVG(q.AnswerCount::numeric),2) AS AvgRecentAnswers,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM Posts p
      WHERE p.OwnerUserId = u.UserId AND p.CreationDate > NOW() - INTERVAL '7 days') THEN 'YES'
    ELSE 'NO'
  END AS IsRecentlyActive,
  ARRAY(
    SELECT ft.NormalizedTag
    FROM FrequentTags ft
    WHERE ft.OwnerUserId = u.UserId AND ft.TagRank <= 3
    ORDER BY ft.TagRank
  ) AS TopTags,
  SUBSTRING(COALESCE(u.DisplayName, 'UNKNOWN'),1,5) || '-' ||
    COALESCE(SPLIT_PART(u.Location, ',', 1), 'nolocation') AS CustomUserKey,
  (COALESCE(vs.UpVotesReceived,0) - COALESCE(vs.DownVotesReceived,0)) / NULLIF(u.Reputation,0)::float AS VoteRepRatio
FROM TopActiveUsers u
LEFT JOIN BadgeAgg ba ON ba.UserId = u.UserId
LEFT JOIN VoteStats vs ON vs.OwnerUserId = u.UserId
LEFT JOIN CommentLengths cl ON cl.UserId = u.UserId
LEFT JOIN RecentQuestions q ON q.OwnerUserId = u.UserId
WHERE u.rn <= 100
GROUP BY
  u.UserId, u.DisplayName, u.Reputation, u.Location, ba.GoldBadges, ba.SilverBadges, ba.BronzeBadges, ba.TotalBadges, ba.LastBadgeDate, vs.UpVotesReceived, vs.DownVotesReceived, vs.TotalVotesReceived, cl.AvgCommentLen, cl.CommentCount
HAVING
  COUNT(DISTINCT q.QuestionId) > 3
ORDER BY
  VoteRepRatio DESC NULLS LAST,
  GoldBadges DESC,
  RecentQuestionsCount DESC,
  u.Reputation DESC
LIMIT 50;