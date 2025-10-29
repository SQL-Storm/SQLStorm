-- {"query": "4747.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 726} 

WITH
  RankedQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.OwnerUserId
        ORDER BY
          p.CreationDate DESC
      ) AS QuestionRank
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1
  ),
  UserActivitySummary AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT ph.PostId) AS TotalPostsEdited,
      MAX(ph.CreationDate) AS LastPostEditDate,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3) THEN 1 ELSE 0 END) AS InitialEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS SubsequentEdits,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      COUNT(DISTINCT c.Id) AS CommentCount,
      MAX(COALESCE(v.CreationDate, '1900-01-01')) AS LastVoteDate
    FROM Users AS u
    LEFT JOIN PostHistory AS ph
      ON u.Id = ph.UserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    LEFT JOIN Comments AS c
      ON u.Id = c.UserId
    LEFT JOIN Votes AS v
      ON u.Id = v.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  )
SELECT
  rq.QuestionId,
  rq.Title AS QuestionTitle,
  uas.DisplayName AS OwnerDisplayName,
  uas.Reputation,
  uas.UserCreationDate,
  uas.TotalPostsEdited,
  uas.LastPostEditDate,
  uas.InitialEdits,
  uas.SubsequentEdits,
  uas.BadgeCount,
  uas.CommentCount,
  uas.LastVoteDate,
  rq2.Title AS SecondLastQuestionTitle,
  CASE
    WHEN rq.QuestionRank = 1 THEN 'Most Recent'
    WHEN rq.QuestionRank = 2 THEN 'Second Most Recent'
    ELSE 'Older'
  END AS QuestionOrdering
FROM RankedQuestions AS rq
JOIN UserActivitySummary AS uas
  ON rq.OwnerUserId = uas.UserId
LEFT JOIN RankedQuestions AS rq2
  ON rq.OwnerUserId = rq2.OwnerUserId
  AND rq2.QuestionRank = rq.QuestionRank + 1
WHERE
  rq.QuestionRank <= 2
  AND uas.Reputation > 1000
  AND uas.LastPostEditDate > uas.UserCreationDate + INTERVAL '30 day'
  AND uas.CommentCount > 50
  AND LOWER(uas.DisplayName) LIKE '%john%'
ORDER BY
  uas.Reputation DESC,
  uas.LastPostEditDate DESC;
