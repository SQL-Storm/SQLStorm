-- {"query": "22048.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1071} 
WITH TopTags AS (
  SELECT TagName, Count
  FROM Tags
  ORDER BY Count DESC
  LIMIT 10
),
TagPosts AS (
  SELECT p.Id, p.OwnerUserId, t.TagName, p.Score, p.AcceptedAnswerId
  FROM Posts p
  CROSS JOIN UNNEST(string_to_array(substring(COALESCE(p.Tags, ''), 2, LENGTH(COALESCE(p.Tags, ''))-2), '><')) AS t(TagName)
  WHERE p.PostTypeId = 1
    AND p.OwnerUserId IS NOT NULL
    AND p.Tags IS NOT NULL
    AND LENGTH(p.Tags) > 2
    AND EXISTS (SELECT 1 FROM TopTags tt WHERE tt.TagName = t.TagName)
),
UserTagActivity AS (
  SELECT tpa.OwnerUserId, tpa.TagName,
         COUNT(*) AS QuestionsPosted,
         AVG(tpa.Score) AS AvgScore,
         COUNT(CASE WHEN tpa.AcceptedAnswerId IS NOT NULL THEN 1 END) AS AcceptedAnswers,
         RANK() OVER (PARTITION BY tpa.TagName ORDER BY COUNT(*) DESC, AVG(tpa.Score) DESC) AS RankInTag,
         SUM(CASE WHEN tpa.Score > 0 THEN tpa.Score ELSE 0 END) / NULLIF(SUM(CASE WHEN tpa.Score > 0 THEN 1 ELSE 0 END), 0) AS PositiveScoreRatio
  FROM TagPosts tpa
  GROUP BY tpa.OwnerUserId, tpa.TagName
  HAVING COUNT(*) > 1
),
UserActivity AS (
  SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate,
         COUNT(DISTINCT b.Id) AS BadgesEarned,
         COUNT(DISTINCT c.Id) AS CommentsMade,
         SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
         AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
         COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS TotalAcceptedAnswers,
         ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
  FROM Users u
  LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class <= 2 AND b.Date > u.CreationDate
  LEFT JOIN Comments c ON u.Id = c.UserId
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1,2)
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
  HAVING COUNT(DISTINCT p.Id) > 5
),
FinalReport AS (
  SELECT ua.Id, ua.DisplayName, ua.Reputation, ua.CreationDate, ua.RepRank, ua.BadgesEarned, ua.CommentsMade, ua.TotalCommentScore, ua.AvgAnswerScore, ua.TotalAcceptedAnswers,
         COALESCE(uta.TagName, 'No Special Tags') AS Tag,
         COALESCE(uta.QuestionsPosted, 0) AS QuestionsPosted,
         COALESCE(uta.AvgScore, 0) AS AvgScore,
         COALESCE(uta.AcceptedAnswers, 0) AS AcceptedAnswers,
         COALESCE(uta.RankInTag, 999) AS RankInTag,
         COALESCE(uta.PositiveScoreRatio, 0) AS PositiveScoreRatio,
         CASE 
           WHEN ua.RepRank <= 100 AND ua.BadgesEarned > 10 THEN 'Top Contributor'
           WHEN ua.RepRank BETWEEN 101 AND 500 THEN 'Active Member'
           ELSE 'Regular User'
         END AS UserCategory
  FROM UserActivity ua
  FULL OUTER JOIN UserTagActivity uta ON ua.Id = uta.OwnerUserId
  WHERE ua.Reputation > 1000
     OR uta.RankInTag <= 5
),
HistoricalInsights AS (
  SELECT fr.Id,
         COUNT(DISTINCT ph.Id) AS PostEdits,
         AVG(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN DATEDIFF('day', fr.CreationDate, ph.CreationDate) END) AS AvgDaysToEdit,
         MAX(CASE WHEN ph.PostHistoryTypeId = 52 THEN 1 ELSE 0 END) AS WasHotQuestion
  FROM FinalReport fr
  LEFT JOIN Posts p ON fr.Id = p.OwnerUserId
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.CreationDate > fr.CreationDate
  GROUP BY fr.Id
)
SELECT fr.*, hi.PostEdits, hi.AvgDaysToEdit, hi.WasHotQuestion,
       (fr.Reputation + COALESCE(fr.BadgesEarned * 50, 0) + COALESCE(fr.TotalCommentScore, 0)) AS ComputedEngagementScore,
       ROW_NUMBER() OVER (ORDER BY ComputedEngagementScore DESC, fr.RepRank ASC) AS FinalRank
FROM FinalReport fr
LEFT JOIN HistoricalInsights hi ON fr.Id = hi.Id
ORDER BY FinalRank ASC, Tag DESC;