-- {"query": "5074.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1156} 
WITH
TopActiveUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE u.CreationDate < (SELECT MAX(CreationDate) FROM Users) -- exclude very last user
  GROUP BY u.Id, u.DisplayName, u.Reputation
  HAVING COUNT(p.Id) > 10
  ORDER BY u.Reputation DESC
  LIMIT 100
),
TagUsage AS (
  SELECT
    unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName,
    COUNT(*) AS TagUsageCount
  FROM Posts
  WHERE PostTypeId = 1
  GROUP BY TagName
),
UserTagActivity AS (
  SELECT
    tu.UserId,
    tag.TagName,
    COUNT(*) AS QuestionsWithTag
  FROM TopActiveUsers tu
  JOIN Posts p ON p.OwnerUserId = tu.UserId AND p.PostTypeId = 1
  CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag(TagName)
  GROUP BY tu.UserId, tag.TagName
),
UserRecentPostScoring AS (
  SELECT
    tu.UserId,
    COUNT(DISTINCT recent.Id) AS RecentPosts,
    COALESCE(AVG(NULLIF(recent.Score, 0)), 0) AS AvgRecentPostScore,
    MAX(recent.CreationDate) AS LastPostDate
  FROM TopActiveUsers tu
  LEFT JOIN Posts recent ON recent.OwnerUserId = tu.UserId
    AND recent.CreationDate > (CURRENT_DATE - INTERVAL '90 days')
  GROUP BY tu.UserId
),
PostLinksAgg AS (
  SELECT
    pl.PostId,
    ARRAY_AGG(DISTINCT rel.Title) FILTER (WHERE rel.PostTypeId = 1) AS RelatedQuestionTitles,
    COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateLinks
  FROM PostLinks pl
  JOIN Posts rel ON rel.Id = pl.RelatedPostId
  GROUP BY pl.PostId
)
SELECT
  u.UserId,
  u.DisplayName,
  u.Reputation,
  u.TotalPosts,
  u.TotalComments,
  u.TotalBadges,
  u.QuestionCount,
  u.AnswerCount,
  urps.RecentPosts,
  urps.AvgRecentPostScore,
  urps.LastPostDate,
  (
    SELECT STRING_AGG(
      t.TagName || '(' || t.TagUsageCount || ')',
      ', '
      ORDER BY t.TagUsageCount DESC, t.TagName
    )
    FROM (
      SELECT uta.TagName, tu2.TagUsageCount
      FROM UserTagActivity uta
      LEFT JOIN TagUsage tu2 ON tu2.TagName = uta.TagName
      WHERE uta.UserId = u.UserId
      ORDER BY tu2.TagUsageCount DESC NULLS LAST, uta.TagName
      LIMIT 5
    ) t
  ) AS TopUserTags,
  (
    SELECT COUNT(*)
    FROM Badges bd
    WHERE bd.UserId = u.UserId
    AND bd.Class = 1
  ) AS GoldBadgeCount,
  COALESCE(
    (
      SELECT COUNT(DISTINCT ph.Id)
      FROM PostHistory ph
      WHERE ph.UserId = u.UserId
        AND ph.PostHistoryTypeId IN (
          SELECT Id FROM PostHistoryTypes WHERE Name LIKE '%Edit%'
        )
        AND ph.CreationDate > (CURRENT_DATE - INTERVAL '1 year')
    ),
    0
  ) AS EditsLastYear,
  ROUND(
    CASE
      WHEN u.TotalPosts > 0 THEN CAST(u.TotalComments AS decimal) / u.TotalPosts
      ELSE NULL
    END,
    2
  ) AS CommentsPerPostRatio,
  (
    SELECT json_agg(
      json_build_object(
        'PostId', p.Id,
        'Title', p.Title,
        'Score', p.Score,
        'ViewCount', p.ViewCount,
        'RelatedQuestionTitles', pla.RelatedQuestionTitles,
        'DuplicateLinks', pla.DuplicateLinks
      )
    )
    FROM Posts p
    LEFT JOIN PostLinksAgg pla ON pla.PostId = p.Id
    WHERE p.OwnerUserId = u.UserId
      AND p.PostTypeId = 1
      AND p.Score = (SELECT MAX(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = u.UserId AND p2.PostTypeId = 1)
      LIMIT 3
  ) AS TopScoringQuestions
FROM TopActiveUsers u
LEFT JOIN UserRecentPostScoring urps ON urps.UserId = u.UserId
ORDER BY u.Reputation DESC, urps.AvgRecentPostScore DESC NULLS LAST, u.TotalPosts DESC
LIMIT 20;