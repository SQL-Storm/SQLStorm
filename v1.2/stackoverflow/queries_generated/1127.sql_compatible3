WITH RankedPosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.AcceptedAnswerId,
    p.Tags,
    u.DisplayName AS OwnerName,
    u.Reputation,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScoreView
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2)
),
TopBadgesPerUser AS (
  SELECT
    b.UserId,
    b.Name,
    COUNT(*) AS BadgeCount,
    ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY COUNT(*) DESC, MAX(b.Date) DESC) AS BadgeRank
  FROM Badges b
  GROUP BY b.UserId, b.Name
),
UserPostStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT ph.PostId) FILTER (WHERE ph.PostHistoryTypeId = 10) AS ClosedPosts,
    COUNT(DISTINCT c.Id) AS CommentCount,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
    COALESCE(SUM(v.BountyAmount), 0) AS TotalBountyEarned,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
QuestionDuplicates AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    p1.Title AS QuestionTitle,
    p2.Title AS DuplicateOfTitle,
    ROW_NUMBER() OVER (PARTITION BY pl.PostId ORDER BY pl.CreationDate DESC) AS DuplicateRank
  FROM PostLinks pl
  INNER JOIN Posts p1 ON pl.PostId = p1.Id AND p1.PostTypeId = 1
  INNER JOIN Posts p2 ON pl.RelatedPostId = p2.Id AND p2.PostTypeId = 1
  WHERE pl.LinkTypeId = 3
),
UserTopTags AS (
  SELECT
    p.OwnerUserId AS UserId,
    tag AS Tag,
    COUNT(*) AS TagUsageCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS TagRank
  FROM Posts p,
  LATERAL (
    SELECT trim(t::varchar) AS tag
    FROM UNNEST(
      CASE
        WHEN p.Tags IS NULL THEN ARRAY[]::varchar[]
        ELSE regexp_split_to_array(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), '><')
      END
    ) AS t
  ) AS tags
  WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1
  GROUP BY p.OwnerUserId, tag
),
BadgeAggregate AS (
  SELECT
    b.UserId,
    COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
  FROM Badges b
  GROUP BY b.UserId
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  ups.TotalPosts,
  ups.ClosedPosts,
  ups.CommentCount,
  ups.AvgQuestionScore,
  ups.AvgAnswerScore,
  ups.UpVotes,
  ups.DownVotes,
  ba.GoldBadges,
  ba.SilverBadges,
  ba.BronzeBadges,
  COALESCE(
    (SELECT STRING_AGG(Tag, ', ')
      FROM UserTopTags utt
      WHERE utt.UserId = u.Id AND utt.TagRank <= 3),
    'No Tags') AS TopTags,
  COALESCE(
    (SELECT STRING_AGG(Name || ' (' || BadgeCount || ')', ', ')
     FROM TopBadgesPerUser tb
     WHERE tb.UserId = u.Id AND tb.BadgeRank <= 3),
    'No Badges'
  ) AS TopBadges,
  COALESCE(rd.DuplicateQuestionsCount, 0) AS DuplicateQuestionsCount
FROM Users u
LEFT JOIN UserPostStats ups ON u.Id = ups.UserId
LEFT JOIN BadgeAggregate ba ON u.Id = ba.UserId
LEFT JOIN (
  SELECT
    p.OwnerUserId,
    COUNT(*) AS DuplicateQuestionsCount
  FROM Posts p
  INNER JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 3
  WHERE p.PostTypeId = 1
  GROUP BY p.OwnerUserId
) rd ON u.Id = rd.OwnerUserId
WHERE ups.TotalPosts > 10
ORDER BY ups.TotalPosts DESC, ups.AvgQuestionScore DESC
LIMIT 100;