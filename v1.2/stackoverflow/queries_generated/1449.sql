-- {"query": "1449.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1360} 

WITH RecentActiveUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Location,
    orders.TotalPosts,
    COALESCE(b.GoldCount,0) AS GoldBadges,
    COALESCE(b.SilverCount,0) AS SilverBadges,
    COALESCE(b.BronzeCount,0) AS BronzeBadges,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, orders.TotalPosts DESC) AS UserRank
  FROM 
    Users u
    LEFT JOIN (
      SELECT 
        OwnerUserId,
        COUNT(*) AS TotalPosts
      FROM Posts
      WHERE OwnerUserId IS NOT NULL
        AND CreationDate > now() - interval '1 year'
      GROUP BY OwnerUserId
    ) orders ON u.Id = orders.OwnerUserId
    LEFT JOIN (
      SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeCount
      FROM Badges 
      GROUP BY UserId
    ) b ON u.Id = b.UserId
  WHERE u.Reputation > 1000
    AND u.LastAccessDate > now() - interval '6 months'
),
UserTopPosts AS (
  SELECT 
    p.OwnerUserId,
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Score,
    p.ViewCount,
    dense_rank() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankInUser
  FROM Posts p
  WHERE p.OwnerUserId IN (SELECT Id FROM RecentActiveUsers)
    AND p.PostTypeId IN (1, 2) 
    AND p.Score IS NOT NULL
),
ExpandedTags AS (
  SELECT
    p.Id AS PostId,
    unnest(string_to_array(trim(both '<>' FROM p.Tags),'><')) AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1 
    AND p.Tags IS NOT NULL
),
TagPopularity AS (
  SELECT
    et.Tag,
    COUNT(DISTINCT et.PostId) AS QuestionCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViewCount
  FROM ExpandedTags et
    JOIN Posts p ON p.Id = et.PostId
  GROUP BY et.Tag
  HAVING COUNT(*) > 100
),
UserCommentInsights AS (
  SELECT
    c.UserId,
    COUNT(*) AS CommentCount,
    AVG(LENGTH(c.Text)) AS AvgCommentLength,
    SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveComments,
    SUM(CASE WHEN c.Score <= 0 THEN 1 ELSE 0 END) AS NonPositiveComments
  FROM Comments c
  WHERE c.UserId IN (SELECT Id FROM RecentActiveUsers)
  GROUP BY c.UserId
),
LinkedDuplicatesCount AS (
  SELECT 
    pl.PostId,
    COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateCount,
    COUNT(*) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedCount
  FROM PostLinks pl
  GROUP BY pl.PostId
),
AggregatedQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    COALESCE(ld.DuplicateCount,0) AS DuplicateCount,
    COALESCE(ld.LinkedCount,0) AS LinkedCount
  FROM Posts p
  LEFT JOIN LinkedDuplicatesCount ld ON p.Id = ld.PostId
  WHERE p.PostTypeId = 1
)
SELECT
  ru.Id AS UserId,
  ru.DisplayName,
  ru.Reputation,
  ru.Location,
  ru.GoldBadges, ru.SilverBadges, ru.BronzeBadges,
  ru.TotalPosts,
  ui.CommentCount, ui.AvgCommentLength,
  OverallTopPosts.PostId AS TopPostId,
  OverallTopPosts.Title AS TopPostTitle,
  OverallTopPosts.Score AS TopPostScore,
  OverallTopPosts.ViewCount AS TopPostViews,
  q.QuestionId, q.Title AS QuestionTitle, q.Score AS QuestionScore,
  q.ViewCount AS QuestionViews, q.DuplicateCount, q.LinkedCount,
  tp.Tag,
  tp.QuestionCount AS TagQuestions, tp.AvgScore AS TagAvgScore, tp.MaxViewCount AS TagMaxView,
  RANK() OVER (PARTITION BY ru.Id ORDER BY OverallTopPosts.Score DESC NULLS LAST) AS PostScoreRank,
  COUNT(*) OVER (PARTITION BY ru.Id) AS PostsByUser,
  CASE 
    WHEN ru.Location IS NULL OR ru.Location = '' THEN 'No location provided'
    ELSE UPPER(ru.Location)
  END AS LocationStandardized,
  COALESCE(
    CASE 
      WHEN ui.CommentCount > 50 THEN 'High commenter'
      WHEN ui.CommentCount BETWEEN 20 AND 50 THEN 'Active commenter'
      ELSE 'Low commenter'
    END, 
    'No comments') AS CommentingTier
FROM RecentActiveUsers ru
LEFT JOIN UserCommentInsights ui ON ru.Id = ui.UserId
LEFT JOIN UserTopPosts OverallTopPosts ON overallTopPosts.OwnerUserId = ru.Id AND OverallTopPosts.RankInUser = 1
LEFT JOIN AggregatedQuestions q ON q.OwnerUserId = ru.Id AND q.Score > (
  SELECT AVG(Score) FROM Posts WHERE OwnerUserId = ru.Id AND PostTypeId = 1
)
LEFT JOIN TagPopularity tp ON tp.Tag = (
  SELECT Tag FROM ExpandedTags et 
  WHERE et.PostId = q.QuestionId 
  ORDER BY 1 LIMIT 1
)
WHERE ru.UserRank <= 50
  AND (
    q.DuplicateCount IS NULL 
    OR q.DuplicateCount < 5
    OR EXISTS (
      SELECT 1 FROM PostHistory ph 
      WHERE ph.PostId = q.QuestionId 
        AND ph.PostHistoryTypeId = 10 
        AND ph.CreationDate > now() - interval '1 year'
    )
  )
ORDER BY ru.Reputation DESC, ru.TotalPosts DESC, TopPostScore DESC;
