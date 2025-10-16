WITH
TopActiveUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Location,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS rn,
    u.DownVotes,
    u.UpVotes
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
    LOWER(SUBSTRING(p.Title FROM 1 FOR 50)) AS TitlePrefix
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
UserQuestionCounts AS (
  SELECT
    p.OwnerUserId,
    COUNT(DISTINCT p.Id) AS UserQuestionCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
    AND p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId
),
BadgeAgg AS (
  SELECT
    b.UserId,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
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
    TRIM(tag) AS NormalizedTag
  FROM Posts p,
  LATERAL (
    SELECT UNNEST(string_to_array(
      -- remove leading '<' and trailing '>' if present, then split on '><'
      CASE
        WHEN p.Tags LIKE '<%' AND p.Tags LIKE '%>' THEN
          CASE WHEN RIGHT(p.Tags,1) = '>' AND LEFT(p.Tags,1) = '<' THEN SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2) ELSE p.Tags END
        ELSE p.Tags
      END
    , '><')) AS tag
  ) s
  WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.Tags IS NOT NULL
),
FrequentTags AS (
  SELECT
    OwnerUserId,
    NormalizedTag,
    COUNT(*) AS TagAppearances,
    RANK() OVER (PARTITION BY OwnerUserId ORDER BY COUNT(*) DESC, NormalizedTag) AS TagRank
  FROM TagUsage
  GROUP BY OwnerUserId, NormalizedTag
),
TopTagsPerUser AS (
  SELECT
    ft.OwnerUserId,
    ft.NormalizedTag,
    ft.TagRank
  FROM FrequentTags ft
  WHERE ft.TagRank <= 3
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
  ba.LastBadgeDate AS LastBadgeDate,
  vs.UpVotesReceived,
  vs.DownVotesReceived,
  vs.TotalVotesReceived,
  cl.AvgCommentLen,
  cl.CommentCount,
  COALESCE(uqc.UserQuestionCount, 0) AS RecentQuestionsCount,
  MAX(q.Score) AS MaxRecentQuestionScore,
  MIN(q.ViewCount) AS MinRecentQuestionViews,
  ROUND(AVG(CAST(q.AnswerCount AS numeric)),2) AS AvgRecentAnswers,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM Posts p
      WHERE p.OwnerUserId = u.UserId
        AND p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7 days') THEN 'YES'
    ELSE 'NO'
  END AS IsRecentlyActive,
  (SELECT STRING_AGG(tt.NormalizedTag, ',' ORDER BY tt.TagRank)
   FROM TopTagsPerUser tt
   WHERE tt.OwnerUserId = u.UserId
  ) AS TopTags,
  SUBSTRING(COALESCE(u.DisplayName, 'UNKNOWN') FROM 1 FOR 5) || '-' ||
    COALESCE(split_part(u.Location, ',', 1), 'nolocation') AS CustomUserKey,
  (COALESCE(vs.UpVotesReceived,0) - COALESCE(vs.DownVotesReceived,0)) / NULLIF(CAST(u.Reputation AS numeric),0) AS VoteRepRatio
FROM TopActiveUsers u
LEFT JOIN BadgeAgg ba ON ba.UserId = u.UserId
LEFT JOIN VoteStats vs ON vs.OwnerUserId = u.UserId
LEFT JOIN CommentLengths cl ON cl.UserId = u.UserId
LEFT JOIN RecentQuestions q ON q.OwnerUserId = u.UserId
LEFT JOIN UserQuestionCounts uqc ON uqc.OwnerUserId = u.UserId
WHERE u.rn <= 100
GROUP BY
  u.UserId,
  u.DisplayName,
  u.Reputation,
  u.Location,
  ba.GoldBadges,
  ba.SilverBadges,
  ba.BronzeBadges,
  ba.TotalBadges,
  ba.LastBadgeDate,
  vs.UpVotesReceived,
  vs.DownVotesReceived,
  vs.TotalVotesReceived,
  cl.AvgCommentLen,
  cl.CommentCount,
  uqc.UserQuestionCount,
  u.rn,
  u.DownVotes,
  u.UpVotes
HAVING
  COALESCE(uqc.UserQuestionCount, 0) > 3
ORDER BY
  VoteRepRatio DESC,
  GoldBadges DESC,
  RecentQuestionsCount DESC,
  u.Reputation DESC
LIMIT 50;