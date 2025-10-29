-- {"query": "4946.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1362} 

WITH
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.AnswerCount,
      p.FavoriteCount,
      p.Score AS QuestionScore,
      p.ViewCount AS QuestionViewCount,
      u.DisplayName AS QuestionOwnerDisplayName,
      u.Reputation AS QuestionOwnerReputation,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts AS p
    JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= DATE('now', '-365 day')
  ),
  TopAnswers AS (
    SELECT
      a.Id AS AnswerId,
      a.ParentId AS QuestionId,
      a.OwnerUserId,
      a.CreationDate AS AnswerCreationDate,
      a.Score AS AnswerScore,
      a.OwnerDisplayName AS AnswerOwnerDisplayName,
      u.Reputation AS AnswerOwnerReputation,
      ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS answer_rn
    FROM Posts AS a
    JOIN Users AS u
      ON a.OwnerUserId = u.Id
    WHERE
      a.PostTypeId = 2
  ),
  QuestionDetails AS (
    SELECT
      rq.QuestionId,
      rq.QuestionTitle,
      rq.QuestionOwnerDisplayName,
      rq.QuestionOwnerReputation,
      rq.QuestionCreationDate,
      rq.AnswerCount,
      rq.FavoriteCount,
      rq.QuestionScore,
      rq.QuestionViewCount,
      MAX(ta.AnswerScore) AS MaxAnswerScore,
      AVG(ta.AnswerScore) AS AvgAnswerScore,
      SUM(CASE WHEN ta.AnswerOwnerReputation > 10000 THEN 1 ELSE 0 END) AS HighRepAnswerCount
    FROM RecentQuestions AS rq
    LEFT JOIN TopAnswers AS ta
      ON rq.QuestionId = ta.QuestionId
    WHERE
      rq.rn <= 500
    GROUP BY
      rq.QuestionId,
      rq.QuestionTitle,
      rq.QuestionOwnerDisplayName,
      rq.QuestionOwnerReputation,
      rq.QuestionCreationDate,
      rq.AnswerCount,
      rq.FavoriteCount,
      rq.QuestionScore,
      rq.QuestionViewCount
  ),
  UserActivity AS (
    SELECT
      UserId,
      COUNT(Id) AS VoteCount,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      SUM(CASE WHEN VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVoteCount
    FROM Votes
    WHERE
      UserId IS NOT NULL
      AND CreationDate >= DATE('now', '-365 day')
    GROUP BY
      UserId
  ),
  QuestionTags AS (
    SELECT
      PostId,
      TagName,
      ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY TagName) AS tag_rn
    FROM Posts
    CROSS JOIN UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(Tags, '<', ''), '>', ''), '')) AS TagName
    WHERE
      PostTypeId = 1
  )
SELECT
  qd.QuestionId,
  qd.QuestionTitle,
  qd.QuestionOwnerDisplayName,
  qd.QuestionOwnerReputation,
  qd.QuestionCreationDate,
  qd.AnswerCount,
  qd.FavoriteCount,
  qd.QuestionScore,
  qd.QuestionViewCount,
  qd.MaxAnswerScore,
  qd.AvgAnswerScore,
  qd.HighRepAnswerCount,
  ua.VoteCount AS UserTotalVotes,
  ua.UpVoteCount AS UserUpVotes,
  ua.DownVoteCount AS UserDownVotes,
  ua.FavoriteVoteCount AS UserFavoriteVotes,
  CASE
    WHEN qd.QuestionScore > 100 AND qd.AnswerCount > 10 THEN 'High Engagement'
    WHEN qd.QuestionScore < 0 THEN 'Negative Score'
    WHEN qd.AnswerCount = 0 THEN 'No Answers'
    ELSE 'Standard'
  END AS QuestionStatus,
  SUBSTRING(qd.QuestionTitle, 1, 50) AS ShortTitle,
  qt1.TagName AS PrimaryTag,
  qt2.TagName AS SecondaryTag,
  (qd.QuestionScore * 1.0 / NULLIF(qd.ViewCount, 0)) * 100 AS ScorePerViewPercentage,
  CASE
    WHEN qd.QuestionOwnerReputation > 50000 AND qd.QuestionOwnerReputation < 100000 THEN 'Expert'
    WHEN qd.QuestionOwnerReputation >= 100000 THEN 'Guru'
    ELSE 'Standard Reputation'
  END AS OwnerReputationTier,
  COALESCE(qd.FavoriteCount, 0) AS NonNullFavoriteCount
FROM QuestionDetails AS qd
LEFT JOIN UserActivity AS ua
  ON qd.OwnerUserId = ua.UserId
LEFT JOIN QuestionTags AS qt1
  ON qd.QuestionId = qt1.PostId AND qt1.tag_rn = 1
LEFT JOIN QuestionTags AS qt2
  ON qd.QuestionId = qt2.PostId AND qt2.tag_rn = 2
WHERE
  qd.QuestionOwnerReputation IS NOT NULL
  AND qd.AvgAnswerScore IS NOT NULL
  AND qd.QuestionScore >= (
    SELECT
      AVG(Score)
    FROM Posts
    WHERE
      PostTypeId = 1
  )
ORDER BY
  qd.QuestionCreationDate DESC
LIMIT 100;
