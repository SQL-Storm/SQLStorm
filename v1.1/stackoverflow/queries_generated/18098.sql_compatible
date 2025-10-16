WITH
  AnswerStats AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId AS AnswererUserId,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS RankByScore,
      COUNT(c.Id) AS CommentCountForAnswer,
      CASE WHEN p.Score > 0 THEN 'Positive' WHEN p.Score < 0 THEN 'Negative' ELSE 'Neutral' END AS ScoreCategory,
      -- compute average comment score per question by aggregating comments grouped by question
      AVG(c.Score) AS AvgCommentScoreForQuestion
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    WHERE
      p.PostTypeId = 2 -- Answers
    GROUP BY
      p.Id,
      p.ParentId,
      p.OwnerUserId,
      p.Score,
      p.CreationDate
  ),
  QuestionDetails AS (
    SELECT
      q.Id AS QuestionId,
      q.Title AS QuestionTitle,
      q.OwnerUserId AS QuestionOwnerUserId,
      q.CreationDate AS QuestionCreationDate,
      q.ViewCount AS QuestionViewCount,
      q.AnswerCount AS QuestionAnswerCount,
      q.FavoriteCount AS QuestionFavoriteCount,
      q.Tags,
      u.DisplayName AS QuestionOwnerDisplayName,
      u.Reputation AS QuestionOwnerReputation,
      DENSE_RANK() OVER (ORDER BY q.ViewCount DESC) AS GlobalViewRank,
      STRING_AGG(t.TagName, ', ' ORDER BY t.TagName) AS FormattedTags
    FROM Posts AS q
    LEFT JOIN Users AS u
      ON q.OwnerUserId = u.Id
    LEFT JOIN LATERAL (
      SELECT unnest(STRING_TO_ARRAY(SUBSTRING(q.Tags, 2, LENGTH(q.Tags) - 2), '><')) AS TagName
    ) t ON TRUE
    WHERE
      q.PostTypeId = 1 -- Questions
    GROUP BY
      q.Id,
      q.Title,
      q.OwnerUserId,
      q.CreationDate,
      q.ViewCount,
      q.AnswerCount,
      q.FavoriteCount,
      q.Tags,
      u.DisplayName,
      u.Reputation
  ),
  UserAnswerActivity AS (
    SELECT
      OwnerUserId AS UserId,
      COUNT(Id) AS TotalAnswers,
      SUM(Score) AS TotalAnswerScore,
      MAX(CreationDate) AS LastAnswerDate
    FROM Posts
    WHERE
      PostTypeId = 2
    GROUP BY
      OwnerUserId
  ),
  HotQuestions AS (
    SELECT
      PostId,
      UserId,
      CreationDate
    FROM PostHistory
    WHERE
      PostHistoryTypeId = 52 -- SelectedHotQuestion
  )
SELECT
  qd.QuestionId,
  qd.QuestionTitle,
  qd.QuestionOwnerDisplayName,
  qd.QuestionOwnerReputation,
  qd.QuestionCreationDate,
  qd.QuestionViewCount,
  qd.QuestionAnswerCount,
  qd.QuestionFavoriteCount,
  qd.FormattedTags,
  (
    SELECT
      COUNT(*)
    FROM Votes AS v
    WHERE
      v.PostId = qd.QuestionId AND v.VoteTypeId = 2
  ) AS UpVoteCountForQuestion,
  COALESCE(as_ranked.RankByScore, -1) AS BestAnswerRank,
  as_ranked.AnswererUserId AS BestAnswererId,
  uaa.TotalAnswers AS TotalAnswersByBestAnswerer,
  uaa.TotalAnswerScore AS TotalScoreOfAnswersByBestAnswerer,
  CASE WHEN hq.PostId IS NOT NULL THEN 'Yes' ELSE 'No' END AS IsHotQuestion,
  CASE WHEN qd.QuestionOwnerReputation > 100000 THEN 'Expert' WHEN qd.QuestionOwnerReputation BETWEEN 50000 AND 100000 THEN 'Senior' WHEN qd.QuestionOwnerReputation BETWEEN 10000 AND 50000 THEN 'Intermediate' ELSE 'Beginner' END AS OwnerExperienceLevel,
  LOWER(COALESCE(qd.QuestionOwnerDisplayName, 'Anonymous')) AS NormalizedOwnerName,
  qd.GlobalViewRank
FROM QuestionDetails AS qd
LEFT JOIN AnswerStats AS as_ranked
  ON qd.QuestionId = as_ranked.QuestionId AND as_ranked.RankByScore = 1
LEFT JOIN UserAnswerActivity AS uaa
  ON as_ranked.AnswererUserId = uaa.UserId
LEFT JOIN HotQuestions AS hq
  ON qd.QuestionId = hq.PostId
WHERE
  qd.QuestionViewCount > 1000
  AND qd.QuestionAnswerCount BETWEEN 5 AND 50
  AND qd.QuestionCreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
  AND qd.QuestionOwnerReputation >= 1000
  AND (
    qd.FormattedTags LIKE '%sql%' OR qd.FormattedTags LIKE '%database%'
  )
UNION ALL
SELECT
  NULL AS QuestionId,
  'Summary Statistic' AS QuestionTitle,
  NULL AS QuestionOwnerDisplayName,
  NULL AS QuestionOwnerReputation,
  NULL AS QuestionCreationDate,
  AVG(qd.QuestionViewCount) AS QuestionViewCount,
  AVG(qd.QuestionAnswerCount) AS QuestionAnswerCount,
  AVG(qd.QuestionFavoriteCount) AS QuestionFavoriteCount,
  NULL AS FormattedTags,
  AVG(
    (
      SELECT
        COUNT(*)
      FROM Votes AS v
      WHERE
        v.PostId = qd.QuestionId AND v.VoteTypeId = 2
    )
  ) AS UpVoteCountForQuestion,
  AVG(COALESCE(as_ranked.RankByScore, -1)) AS BestAnswerRank,
  NULL AS BestAnswererId,
  AVG(uaa.TotalAnswers) AS TotalAnswersByBestAnswerer,
  AVG(uaa.TotalAnswerScore) AS TotalScoreOfAnswersByBestAnswerer,
  NULL AS IsHotQuestion,
  NULL AS OwnerExperienceLevel,
  'Average' AS NormalizedOwnerName,
  AVG(qd.GlobalViewRank) AS GlobalViewRank
FROM QuestionDetails AS qd
LEFT JOIN AnswerStats AS as_ranked
  ON qd.QuestionId = as_ranked.QuestionId AND as_ranked.RankByScore = 1
LEFT JOIN UserAnswerActivity AS uaa
  ON as_ranked.AnswererUserId = uaa.UserId
WHERE
  qd.QuestionViewCount > 1000
  AND qd.QuestionAnswerCount BETWEEN 5 AND 50
  AND qd.QuestionCreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
  AND qd.QuestionOwnerReputation >= 1000
  AND (
    qd.FormattedTags LIKE '%sql%' OR qd.FormattedTags LIKE '%database%'
  );