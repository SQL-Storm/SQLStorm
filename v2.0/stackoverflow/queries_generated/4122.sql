-- {"query": "4122.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1703} 

WITH
  AnswerScores AS (
    SELECT
      p.Id AS PostId,
      SUM(v.VoteTypeId) AS TotalScore,
      COUNT(v.Id) AS TotalVotes,
      CASE
        WHEN COUNT(v.Id) > 0
        THEN CAST(SUM(v.VoteTypeId) AS REAL) / COUNT(v.Id)
        ELSE 0
      END AS AvgVoteType
    FROM Posts AS p
    JOIN Votes AS v
      ON p.Id = v.PostId
    WHERE
      p.PostTypeId = 2 -- Answers
      AND v.VoteTypeId IN (2, 3) -- UpVotes and DownVotes
    GROUP BY
      p.Id
  ),
  QuestionEngagement AS (
    SELECT
      q.Id AS QuestionId,
      q.Title,
      q.CreationDate AS QuestionCreationDate,
      COALESCE(q.AnswerCount, 0) AS AnswerCount,
      COALESCE(q.CommentCount, 0) AS CommentCount,
      COALESCE(q.FavoriteCount, 0) AS FavoriteCount,
      COALESCE(q.ViewCount, 0) AS ViewCount,
      CASE
        WHEN q.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed,
      COALESCE(MAX(c.CreationDate), '1900-01-01') AS LastCommentDate,
      COALESCE(MAX(ph.CreationDate), '1900-01-01') AS LastHistoryDate,
      COALESCE(MAX(p_hist.CreationDate), '1900-01-01') AS LastPostHistoryDate
    FROM Posts AS q
    LEFT JOIN Comments AS c
      ON q.Id = c.PostId
    LEFT JOIN PostHistory AS ph
      ON q.Id = ph.PostId
    LEFT JOIN PostHistory AS p_hist -- To get the most recent edit date
      ON q.Id = p_hist.PostId
    WHERE
      q.PostTypeId = 1 -- Questions
    GROUP BY
      q.Id,
      q.Title,
      q.CreationDate,
      q.AnswerCount,
      q.CommentCount,
      q.FavoriteCount,
      q.ViewCount,
      q.ClosedDate
  ),
  UserReputationRank AS (
    SELECT
      UserId,
      Reputation,
      ROW_NUMBER() OVER (ORDER BY Reputation DESC, CreationDate ASC) AS ReputationRank
    FROM Users
  ),
  TopAnswers AS (
    SELECT
      a.Id AS AnswerId,
      a.ParentId AS QuestionId,
      a.Score AS AnswerScore,
      COALESCE(ascores.TotalVotes, 0) AS TotalAnswerVotes,
      COALESCE(ascores.AvgVoteType, 0) AS AvgAnswerVoteType,
      a.CreationDate AS AnswerCreationDate,
      ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY COALESCE(ascores.TotalVotes, 0) DESC, a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts AS a
    LEFT JOIN AnswerScores AS ascores
      ON a.Id = ascores.PostId
    WHERE
      a.PostTypeId = 2 -- Answers
  )
SELECT
  qe.QuestionId,
  qe.Title,
  qe.QuestionCreationDate,
  qe.AnswerCount,
  qe.CommentCount,
  qe.FavoriteCount,
  qe.ViewCount,
  qe.IsClosed,
  DATEDIFF(DAY, qe.QuestionCreationDate, qe.LastCommentDate) AS DaysSinceLastComment,
  DATEDIFF(DAY, qe.QuestionCreationDate, qe.LastHistoryDate) AS DaysSinceLastPostHistoryEntry,
  DATEDIFF(DAY, qe.QuestionCreationDate, qe.LastPostHistoryDate) AS DaysSinceLastEdit,
  CASE
    WHEN qe.ViewCount > 10000 THEN 'High Traffic'
    WHEN qe.ViewCount > 1000 THEN 'Medium Traffic'
    ELSE 'Low Traffic'
  END AS TrafficCategory,
  CASE
    WHEN ta.AnswerRank = 1 THEN 'Best Answer'
    WHEN ta.AnswerRank <= 5 THEN 'Top 5 Answer'
    ELSE 'Other Answer'
  END AS AnswerQualityRank,
  COALESCE(usr.DisplayName, 'Unknown User') AS OwnerDisplayName,
  COALESCE(ur.Reputation, 0) AS OwnerReputation,
  ur.ReputationRank,
  CASE
    WHEN qe.LastCommentDate > qe.LastPostHistoryDate THEN 'Comment Activity Dominant'
    WHEN qe.LastPostHistoryDate > qe.LastCommentDate THEN 'Edit Activity Dominant'
    ELSE 'Balanced Activity'
  END AS ActivityDominance,
  -- Simulating a complex string operation and NULL handling
  CASE
    WHEN qe.Title LIKE '%[Tt]utorial%' OR qe.Title LIKE '%[Hh]ow [Tt]o%' THEN 'Instructional'
    WHEN qe.Title IS NULL THEN 'No Title'
    ELSE 'General'
  END AS TitleType,
  -- Join to Posts for Accepted Answer details
  pa.Id AS AcceptedAnswerId,
  pa.Score AS AcceptedAnswerScore,
  COALESCE(pascores.TotalVotes, 0) AS AcceptedAnswerTotalVotes,
  CASE
    WHEN EXISTS (SELECT 1 FROM PostLinks AS pl WHERE pl.PostId = qe.QuestionId AND pl.LinkTypeId = 3) THEN 'Has Duplicate Link'
    ELSE 'No Duplicate Link'
  END AS DuplicateLinkStatus,
  -- CTE that joins to itself to find questions linked to the current question (indirect duplicates)
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl_inner
      JOIN PostLinks AS pl_outer
        ON pl_inner.RelatedPostId = pl_outer.PostId
      WHERE
        pl_inner.PostId = qe.QuestionId AND pl_inner.LinkTypeId = 3 AND pl_outer.LinkTypeId = 3
    ) THEN 'Indirect Duplicate Chain'
    ELSE 'No Indirect Duplicate Chain'
  END AS IndirectDuplicateChainStatus
FROM QuestionEngagement AS qe
LEFT JOIN Posts AS u -- To get owner details
  ON qe.QuestionId = u.Id
LEFT JOIN Users AS usr
  ON u.OwnerUserId = usr.Id
LEFT JOIN UserReputationRank AS ur
  ON usr.Id = ur.UserId
LEFT JOIN TopAnswers AS ta
  ON qe.QuestionId = ta.QuestionId AND ta.AnswerRank = 1 -- Focus on the best answer for each question
LEFT JOIN Posts AS pa -- Details of the accepted answer
  ON qe.QuestionId = pa.AcceptedAnswerId
LEFT JOIN AnswerScores AS pascores -- Score details of the accepted answer
  ON pa.Id = pascores.PostId
WHERE
  qe.ViewCount > 500
  AND qe.AnswerCount > 0
  AND qe.QuestionCreationDate >= '2023-01-01'
  AND (
    usr.Id IS NOT NULL OR ur.ReputationRank IS NOT NULL
  )
ORDER BY
  qe.ViewCount DESC,
  qe.QuestionCreationDate DESC
LIMIT 100;
