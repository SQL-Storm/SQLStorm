WITH UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT a.Id) AS TotalAnswers,
    COUNT(DISTINCT q.Id) AS TotalQuestions,
    COALESCE(SUM(p.Score), 0) AS TotalPostScore,
    COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
    COALESCE(MAX(u.Reputation), 0) AS MaxReputation,
    MIN(u.CreationDate) AS FirstSeen,
    MAX(u.LastAccessDate) AS LastSeen,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Posts q ON q.OwnerUserId = u.Id AND q.PostTypeId = 1
  LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.CreationDate, u.LastAccessDate
),
MostEditedPosts AS (
  SELECT
    ph.PostId,
    COUNT(*) AS EditCount
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4, 5, 6)
  GROUP BY ph.PostId
),
PostTags AS (
  SELECT
    p.Id,
    TRIM(tag) AS Tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT
      CASE
        WHEN p.Tags IS NULL OR p.Tags = '' THEN NULL
        ELSE regexp_replace(value, '^<|>$', '')
      END AS tag
    FROM UNNEST(
      CASE
        WHEN p.Tags IS NULL OR p.Tags = '' THEN ARRAY[]::text[]
        ELSE string_to_array(
          replace(
            substring(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2),
            '><',
            '||'
          ),
          '||'
        )
      END
    ) AS t(value)
  ) s
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
TopTags AS (
  SELECT
    pt.Tag,
    COUNT(*) AS TagCount
  FROM PostTags pt
  GROUP BY pt.Tag
  ORDER BY TagCount DESC
  LIMIT 10
),
TagActivity AS (
  SELECT
    pt.Tag,
    COUNT(DISTINCT p.Id) AS QuestionCount,
    COALESCE(SUM(p.Score), 0) AS TotalScore,
    AVG(p.Score) AS AvgScore,
    COALESCE(SUM(p.ViewCount), 0) AS TotalViews,
    AVG(p.ViewCount) AS AvgViews
  FROM PostTags pt
  JOIN Posts p ON pt.Id = p.Id
  WHERE pt.Tag IN (SELECT Tag FROM TopTags)
  GROUP BY pt.Tag
),
DuplicateClusters AS (
  SELECT
    pl.RelatedPostId AS CanonicalId,
    COUNT(DISTINCT pl.PostId) AS DuplicateCount,
    MAX(p.Score) AS MaxScore,
    AVG(p.Score) AS AvgScore
  FROM PostLinks pl
  JOIN Posts p ON p.Id = pl.PostId
  WHERE pl.LinkTypeId = 3
  GROUP BY pl.RelatedPostId
  HAVING COUNT(DISTINCT pl.PostId) >= 5
),
TopTagActivityFlattened AS (
  SELECT
    ta.Tag,
    ta.QuestionCount,
    ta.AvgScore,
    ta.AvgViews,
    ROW_NUMBER() OVER (ORDER BY ta.QuestionCount DESC) AS rn
  FROM TagActivity ta
),
UserTopTags AS (
  SELECT
    (t.Tag || ' (' || CAST(t.QuestionCount AS varchar) || ' q, ' || CAST(ROUND(CAST(t.AvgScore AS numeric), 2) AS varchar) || ' avg score, ' || CAST(ROUND(CAST(t.AvgViews AS numeric), 2) AS varchar) || ' avg views)') AS TagSummary,
    t.rn
  FROM (
    SELECT
      Tag,
      QuestionCount,
      AvgScore,
      AvgViews,
      ROW_NUMBER() OVER (ORDER BY QuestionCount DESC) AS rn
    FROM TagActivity
  ) t
  WHERE t.rn <= 3
),
UserTopTagsCombined AS (
  SELECT
    STRING_AGG(TagSummary, '; ' ORDER BY rn) AS TopTagActivity
  FROM UserTopTags
)
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.TotalPosts,
  ua.TotalQuestions,
  ua.TotalAnswers,
  ua.TotalPostScore,
  ua.TotalCommentScore,
  ua.MaxReputation,
  ua.BadgeCount,
  ua.GoldBadges,
  ua.SilverBadges,
  ua.BronzeBadges,
  ua.FirstSeen,
  ua.LastSeen,
  COALESCE(mp.EditCount, 0) AS MostEditsOnAnyPost,
  COALESCE(utt.TopTagActivity, '') AS TopTagActivity,
  (
    SELECT COALESCE(SUM(dc.DuplicateCount), 0)
    FROM DuplicateClusters dc
    JOIN Posts q ON q.Id = dc.CanonicalId AND q.OwnerUserId = ua.UserId
  ) AS DuplicateClustersAsCanonical
FROM UserActivity ua
LEFT JOIN (
  SELECT
    p.OwnerUserId,
    MAX(COALESCE(mp.EditCount, 0)) AS EditCount
  FROM Posts p
  LEFT JOIN MostEditedPosts mp ON mp.PostId = p.Id
  WHERE p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId
) mp ON mp.OwnerUserId = ua.UserId
CROSS JOIN LATERAL (
  SELECT TopTagActivity FROM UserTopTagsCombined
) utt
ORDER BY ua.MaxReputation DESC, ua.TotalPosts DESC
LIMIT 50;