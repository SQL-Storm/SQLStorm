-- {"query": "4333.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 958}
WITH
  TopUsers AS (
    SELECT
      Users.Id AS UserId,
      Users.DisplayName,
      Users.Reputation,
      COUNT(ph.PostId) AS PostEdits
    FROM Users
    JOIN PostHistory AS ph
      ON Users.Id = ph.UserId
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY
      Users.Id,
      Users.DisplayName,
      Users.Reputation
    ORDER BY
      PostEdits DESC
    LIMIT 10
  ),
  PostScores AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.Score,
      pt.Name AS PostType,
      COUNT(c.Id) AS CommentCount,
      COALESCE(AVG(v.VoteTypeId), 0) AS AvgVoteType
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    WHERE
      p.Score > 0
    GROUP BY
      p.Id,
      p.Title,
      p.Score,
      pt.Name
    HAVING
      COUNT(c.Id) > 5 OR p.Score > 10
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.CreationDate,
      COUNT(DISTINCT p.Id) AS QuestionsAsked,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswersGiven,
      SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.AnswerCount,0) ELSE 0 END) AS TotalAnswersReceived
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    WHERE
      u.Reputation > 1000
    GROUP BY
      u.Id,
      u.DisplayName,
      u.CreationDate
    HAVING
      COUNT(DISTINCT p.Id) > 50
  )
SELECT
  tu.DisplayName AS TopUserDisplayName,
  tu.Reputation AS TopUserReputation,
  pa.QuestionsAsked,
  pa.AnswersGiven,
  COALESCE(ps.Title, 'N/A') AS HighScorePostTitle,
  ps.Score AS HighScore,
  ps.PostType,
  ps.AvgVoteType,
  CASE
    WHEN ps.AvgVoteType = 2 THEN 'Upvoted'
    WHEN ps.AvgVoteType = 3 THEN 'Downvoted'
    ELSE 'Neutral/Other'
  END AS VoteSentiment,
  CASE
    WHEN pa.TotalAnswersReceived > 200 THEN 'Prolific Answerer'
    WHEN pa.TotalAnswersReceived BETWEEN 100 AND 200 THEN 'Active Answerer'
    ELSE 'Moderately Active Answerer'
  END AS AnswerActivityLevel,
  (SUBSTR(tu.DisplayName, 1, 3) || '-' || RIGHT(CAST(tu.Reputation AS VARCHAR), 3)) AS UserIdentifier,
  CASE
    WHEN (
      SELECT
        COUNT(*)
      FROM Badges AS b
      WHERE
        b.UserId = tu.UserId AND b.Name LIKE '%Master%'
    ) > 0 THEN 'Has Master Badge'
    ELSE 'No Master Badge'
  END AS BadgeStatus
FROM TopUsers AS tu
LEFT JOIN UserActivity AS pa
  ON tu.UserId = pa.UserId
LEFT JOIN PostScores AS ps
  ON ps.PostId = (
    SELECT
      p2.Id
    FROM Posts p2
    JOIN PostScores ps2 ON ps2.PostId = p2.Id
    ORDER BY
      p2.Score DESC
    LIMIT 1
  )
WHERE
  (tu.Reputation IS NOT NULL AND tu.Reputation > 50000) OR (pa.QuestionsAsked IS NOT NULL AND pa.QuestionsAsked > 500)
GROUP BY
  tu.DisplayName,
  tu.Reputation,
  pa.QuestionsAsked,
  pa.AnswersGiven,
  ps.Title,
  ps.Score,
  ps.PostType,
  ps.AvgVoteType,
  pa.TotalAnswersReceived,
  tu.UserId
ORDER BY
  tu.Reputation DESC NULLS LAST,
  pa.QuestionsAsked DESC NULLS LAST;