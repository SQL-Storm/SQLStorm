-- {"query": "4971.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1534}
WITH
  QuestionDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.ViewCount AS QuestionViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation AS OwnerReputation,
      ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM Posts AS p
    JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.ClosedDate IS NULL
  ),
  AnswerAggregates AS (
    SELECT
      ParentId,
      COUNT(Id) AS AnswerCount,
      SUM(CASE WHEN Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreAnswerCount,
      AVG(Score) AS AverageAnswerScore,
      MAX(Score) AS MaxAnswerScore,
      SUM(CASE WHEN EXISTS (SELECT 1 FROM Posts AS Acc WHERE Acc.Id = Posts.Id AND Acc.AcceptedAnswerId = Posts.Id) THEN 1 ELSE 0 END) AS IsAcceptedAnswerPresent
    FROM Posts
    WHERE
      PostTypeId = 2
    GROUP BY
      ParentId
  ),
  CommentActivity AS (
    SELECT
      PostId,
      COUNT(Id) AS CommentCount,
      SUM(CASE WHEN Score > 2 THEN 1 ELSE 0 END) AS HighScoreCommentCount,
      AVG(LENGTH(Text)) AS AverageCommentLength,
      MAX(CreationDate) AS LatestCommentDate
    FROM Comments
    GROUP BY
      PostId
  ),
  PostHistoryStats AS (
    SELECT
      PostId,
      COUNT(CASE WHEN PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS EditCount,
      MAX(CreationDate) AS LastEditDate
    FROM PostHistory
    WHERE
      PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13, 14, 15, 19, 20, 35, 36)
    GROUP BY
      PostId
  ),
  UserActivity AS (
    SELECT
      UserId,
      COUNT(Id) AS VoteCount,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      SUM(CASE WHEN VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCount,
      MAX(CreationDate) AS LastVoteDate
    FROM Votes
    GROUP BY
      UserId
  ),
  TagInfo AS (
    SELECT
      t.TagName,
      t.Count AS TagPostCount,
      (SELECT COUNT(*) FROM Posts AS p2 WHERE p2.Tags LIKE '%<' || t.TagName || '>%' AND p2.PostTypeId = 1) AS QuestionsWithTag
    FROM Tags AS t
  )
SELECT
  qd.QuestionId,
  qd.QuestionTitle,
  qd.OwnerDisplayName,
  qd.OwnerReputation,
  qd.QuestionScore,
  qd.QuestionViewCount,
  COALESCE(aa.AnswerCount, 0) AS TotalAnswers,
  COALESCE(aa.PositiveScoreAnswerCount, 0) AS PositiveAnswers,
  aa.AverageAnswerScore,
  aa.IsAcceptedAnswerPresent,
  COALESCE(ca.CommentCount, 0) AS TotalComments,
  ca.HighScoreCommentCount,
  ca.AverageCommentLength,
  COALESCE(phs.EditCount, 0) AS TotalEdits,
  phs.LastEditDate,
  COALESCE(ua.VoteCount, 0) AS UserTotalVotes,
  ua.UpVoteCount,
  ua.DownVoteCount,
  ua.FavoriteCount,
  ua.LastVoteDate,
  CASE
    WHEN qd.QuestionCreationDate < (cast('2024-10-01' as date) - INTERVAL '365 days') AND qd.OwnerReputation < 1000 THEN 'Low Activity User'
    WHEN qd.QuestionScore > 1000 AND qd.QuestionViewCount > 100000 THEN 'Highly Viewed & Scored'
    WHEN COALESCE(aa.AnswerCount, 0) > 20 AND aa.AverageAnswerScore > 5 THEN 'High Engagement Answered'
    WHEN COALESCE(ca.CommentCount, 0) > 50 AND COALESCE(ca.HighScoreCommentCount, 0) > 10 THEN 'Discussion Heavy'
    WHEN COALESCE(phs.EditCount, 0) > 15 THEN 'Frequently Edited'
    WHEN qd.FavoriteCount > 100 THEN 'Highly Favorited'
    ELSE 'Standard Activity'
  END AS PerformanceCategory,
  STRING_AGG(DISTINCT ta.TagName, ',') AS RelatedTags
FROM QuestionDetails AS qd
LEFT JOIN AnswerAggregates AS aa
  ON qd.QuestionId = aa.ParentId
LEFT JOIN CommentActivity AS ca
  ON qd.QuestionId = ca.PostId
LEFT JOIN PostHistoryStats AS phs
  ON qd.QuestionId = phs.PostId
LEFT JOIN UserActivity AS ua
  ON qd.OwnerUserId = ua.UserId
LEFT JOIN Posts AS q_tags
  ON qd.QuestionId = q_tags.Id
LEFT JOIN TagInfo AS ta
  ON q_tags.Tags LIKE '%' || ta.TagName || '%'
WHERE
  qd.rn <= 500
GROUP BY
  qd.QuestionId,
  qd.QuestionTitle,
  qd.OwnerDisplayName,
  qd.OwnerReputation,
  qd.QuestionScore,
  qd.QuestionViewCount,
  aa.AnswerCount,
  aa.PositiveScoreAnswerCount,
  aa.AverageAnswerScore,
  aa.IsAcceptedAnswerPresent,
  ca.CommentCount,
  ca.HighScoreCommentCount,
  ca.AverageCommentLength,
  phs.EditCount,
  phs.LastEditDate,
  ua.VoteCount,
  ua.UpVoteCount,
  ua.DownVoteCount,
  ua.FavoriteCount,
  ua.LastVoteDate,
  qd.QuestionCreationDate,
  qd.FavoriteCount,
  qd.OwnerUserId,
  qd.rn
ORDER BY
  qd.rn;