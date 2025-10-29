-- {"query": "4642.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1100}
WITH
  RecentQuestions AS (
    SELECT
      Id,
      OwnerUserId,
      Title,
      Tags,
      Score,
      AnswerCount,
      ViewCount,
      CreationDate,
      ROW_NUMBER() OVER (ORDER BY CreationDate DESC) AS rn
    FROM
      Posts
    WHERE
      PostTypeId = 1
      AND CreationDate >= (cast('2024-10-01' as date) - INTERVAL '365 days')
  ),
  HighScoringQuestions AS (
    SELECT
      Id,
      OwnerUserId,
      Title,
      Tags,
      Score,
      AnswerCount,
      ViewCount,
      CreationDate,
      ROW_NUMBER() OVER (ORDER BY Score DESC, ViewCount DESC) AS rnk
    FROM
      Posts
    WHERE
      PostTypeId = 1
      AND Score > 50
      AND AnswerCount > 5
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS QuestionsAsked,
      SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreQuestions,
      COUNT(DISTINCT c.Id) AS CommentsMade,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven
    FROM
      Users AS u
    LEFT JOIN
      Posts AS p
      ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN
      Comments AS c
      ON u.Id = c.UserId
    LEFT JOIN
      Votes AS v
      ON u.Id = v.UserId AND v.VoteTypeId = 2
    WHERE
      u.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '730 days')
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  TagPopularity AS (
    SELECT
      t.TagName,
      COUNT(DISTINCT p.Id) AS TaggedQuestionCount,
      AVG(p.Score) AS AverageTagScore,
      SUM(p.ViewCount) AS TotalTagViews
    FROM
      Tags AS t
    JOIN
      Posts AS p
      ON t.TagName = SUBSTRING(p.Tags FROM 2 FOR (POSITION('>' IN p.Tags) - 2))
    WHERE
      p.PostTypeId = 1
    GROUP BY
      t.TagName
  )
SELECT
  rq.Title AS QuestionTitle,
  rq.CreationDate AS QuestionCreationDate,
  ue.DisplayName AS OwnerDisplayName,
  ue.Reputation AS OwnerReputation,
  hsq.Score AS HighScore,
  hsq.AnswerCount AS HighAnswerCount,
  tp.TagName,
  tp.TaggedQuestionCount,
  tp.AverageTagScore,
  CASE
    WHEN ue.UpvotesGiven > 1000 THEN 'Highly Active'
    WHEN ue.UpvotesGiven > 500 THEN 'Moderately Active'
    ELSE 'Less Active'
  END AS UserActivityLevel,
  COALESCE(ue.CommentsMade, 0) AS TotalComments,
  CASE
    WHEN hsq.rnk IS NOT NULL THEN 'Featured'
    ELSE 'Standard'
  END AS QuestionStatus,
  (
    SELECT
      COUNT(*)
    FROM
      PostLinks AS pl
    WHERE
      pl.PostId = rq.Id AND pl.LinkTypeId = 3
  ) AS DuplicateLinksCount,
  UPPER(SUBSTRING(ue.DisplayName FROM 1 FOR 3)) || '-' || RIGHT('000' || CAST(ue.UserId AS VARCHAR), 4) AS UserIdentifier,
  LENGTH(rq.Tags) AS TagLength,
  CASE
    WHEN tp.TotalTagViews > 1000000 THEN 'Very Popular Tag'
    WHEN tp.TotalTagViews > 500000 THEN 'Popular Tag'
    ELSE 'Common Tag'
  END AS TagPopularity
FROM
  RecentQuestions AS rq
LEFT JOIN
  HighScoringQuestions AS hsq
  ON rq.Id = hsq.Id
LEFT JOIN
  UserEngagement AS ue
  ON rq.OwnerUserId = ue.UserId
LEFT JOIN
  TagPopularity AS tp
  ON SUBSTRING(rq.Tags FROM 2 FOR (POSITION('>' IN rq.Tags) - 2)) = tp.TagName
WHERE
  (
    ue.Reputation > 10000 OR (hsq.rnk IS NOT NULL AND hsq.rnk < 10)
  )
  AND ue.UserId IS NOT NULL
  AND SUBSTRING(rq.Tags FROM 2 FOR (POSITION('>' IN rq.Tags) - 2)) <> 'sql'
ORDER BY
  rq.CreationDate DESC,
  ue.Reputation DESC;