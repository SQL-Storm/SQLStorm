-- {"query": "4682.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1823} 

WITH
  QuestionDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.CreationDate AS QuestionCreationDate,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation AS OwnerReputation,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount AS QuestionViewCount,
      p.Score AS QuestionScore,
      COALESCE(
        (
          SELECT
            SUM(ph.Text::INT)
          FROM
            PostHistory ph
          WHERE
            ph.PostId = p.Id
            AND ph.PostHistoryTypeId = 10 -- Post Closed
        ),
        0
      ) AS CloseVotesCount,
      p.ClosedDate,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed
    FROM
      Posts p
      JOIN Users u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1 -- Question
  ),
  AnswerStats AS (
    SELECT
      ParentId AS QuestionId,
      COUNT(Id) AS AnswerCount,
      SUM(Score) AS TotalAnswerScore,
      COUNT(CASE WHEN AcceptedAnswerId IS NOT NULL THEN Id END) AS AcceptedAnswerCount,
      AVG(Score) AS AverageAnswerScore,
      MAX(Score) AS MaxAnswerScore
    FROM
      Posts
    WHERE
      PostTypeId = 2 -- Answer
    GROUP BY
      ParentId
  ),
  CommentAnalysis AS (
    SELECT
      c.PostId,
      COUNT(c.Id) AS CommentCount,
      SUM(c.Score) AS TotalCommentScore,
      AVG(c.Score) AS AverageCommentScore,
      MAX(c.Score) AS MaxCommentScore,
      STRING_AGG(LEFT(c.Text, 50), ' | ') AS SampleCommentTexts
    FROM
      Comments c
    GROUP BY
      c.PostId
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
      COUNT(DISTINCT c.Id) AS CommentCount,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      SUM(p.Score) AS TotalPostScore,
      u.Reputation
    FROM
      Users u
      LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
      LEFT JOIN Comments c
      ON u.Id = c.UserId
      LEFT JOIN Badges b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.Reputation
  ),
  TagPopularity AS (
    SELECT
      t.TagName,
      t.Count AS TagCount,
      COALESCE(
        (
          SELECT
            COUNT(*)
          FROM
            Posts p
          WHERE
            p.PostTypeId = 1
            AND p.Tags LIKE '%' || t.TagName || '%'
        ),
        0
      ) AS QuestionsWithTag
    FROM
      Tags t
  )
SELECT
  qd.QuestionId,
  qd.QuestionTitle,
  qd.QuestionCreationDate,
  qd.OwnerDisplayName,
  qd.OwnerReputation,
  COALESCE(as.AnswerCount, 0) AS TotalAnswers,
  COALESCE(as.TotalAnswerScore, 0) AS TotalAnswerScore,
  COALESCE(as.AcceptedAnswerCount, 0) AS AcceptedAnswers,
  COALESCE(as.AverageAnswerScore, 0) AS AverageAnswerScore,
  COALESCE(ca.CommentCount, 0) AS TotalCommentsOnQuestion,
  COALESCE(ca.TotalCommentScore, 0) AS TotalCommentScoreOnQuestion,
  COALESCE(ca.AverageCommentScore, 0) AS AverageCommentScoreOnQuestion,
  qd.FavoriteCount,
  qd.QuestionViewCount,
  qd.QuestionScore,
  qd.CloseVotesCount,
  qd.ClosedDate,
  ua.QuestionCount AS OwnerQuestionsPosted,
  ua.AnswerCount AS OwnerAnswersPosted,
  ua.CommentCount AS OwnerCommentsPosted,
  ua.BadgeCount AS OwnerBadgesEarned,
  ua.Reputation AS OwnerReputationOverall,
  STRING_AGG(tp.TagName, ', ') WITHIN GROUP (
    ORDER BY
      tp.TagCount DESC
  ) AS TopQuestionTags,
  ROW_NUMBER() OVER (
    ORDER BY
      qd.QuestionScore DESC,
      qd.QuestionCreationDate ASC
  ) AS ScoreRank,
  LAG(qd.QuestionTitle, 1, 'No previous question') OVER (
    ORDER BY
      qd.QuestionCreationDate
  ) AS PreviousQuestionTitle,
  LEAD(qd.QuestionTitle, 1, 'No subsequent question') OVER (
    ORDER BY
      qd.QuestionCreationDate
  ) AS NextQuestionTitle,
  CASE
    WHEN qd.OwnerReputation > 100000 THEN 'Legendary'
    WHEN qd.OwnerReputation > 50000 THEN 'Expert'
    WHEN qd.OwnerReputation > 10000 THEN 'Advanced'
    WHEN qd.OwnerReputation > 1000 THEN 'Intermediate'
    ELSE 'Novice'
  END AS OwnerReputationTier,
  CASE
    WHEN qd.OwnerDisplayName LIKE '% %' THEN UPPER(SUBSTRING(qd.OwnerDisplayName FROM POSITION(' ' IN qd.OwnerDisplayName) + 1 FOR 1))
    ELSE UPPER(SUBSTRING(qd.OwnerDisplayName FROM 1 FOR 1))
  END AS OwnerLastNameInitial,
  qd.QuestionTitle || ' (' || COALESCE(CAST(qd.AnswerCount AS VARCHAR), '0') || ' Answers)' AS QuestionSummary,
  ua.TotalPostScore AS OwnerTotalPostScore
FROM
  QuestionDetails qd
  LEFT JOIN AnswerStats as
  ON qd.QuestionId = as.QuestionId
  LEFT JOIN CommentAnalysis ca
  ON qd.QuestionId = ca.PostId
  LEFT JOIN UserActivity ua
  ON qd.OwnerUserId = ua.UserId
  LEFT JOIN (
    SELECT DISTINCT
      p.Id,
      t.TagName
    FROM
      Posts p
      CROSS JOIN UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), '')) AS t(TagName)
    WHERE
      p.PostTypeId = 1
  ) tp
  ON qd.QuestionId = tp.Id
WHERE
  qd.OwnerReputation > 500 -- Filter for users with at least some reputation
  AND qd.QuestionScore > 10 -- Filter for questions with at least some score
  AND qd.AnswerCount > 0 -- Only consider questions with answers
  AND qd.QuestionCreationDate >= NOW() - INTERVAL '365 day' -- Last year
GROUP BY
  qd.QuestionId,
  qd.QuestionTitle,
  qd.QuestionCreationDate,
  qd.OwnerDisplayName,
  qd.OwnerReputation,
  as.AnswerCount,
  as.TotalAnswerScore,
  as.AcceptedAnswerCount,
  as.AverageAnswerScore,
  ca.CommentCount,
  ca.TotalCommentScore,
  ca.AverageCommentScore,
  qd.FavoriteCount,
  qd.QuestionViewCount,
  qd.QuestionScore,
  qd.CloseVotesCount,
  qd.ClosedDate,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.CommentCount,
  ua.BadgeCount,
  ua.Reputation,
  ua.TotalPostScore
ORDER BY
  qd.QuestionScore DESC
LIMIT 100;
