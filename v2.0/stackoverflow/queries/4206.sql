-- {"query": "4206.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1125}
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ph.Comment,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.ViewCount AS QuestionViewCount,
      p.FavoriteCount AS QuestionFavoriteCount,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS question_rank,
      p.Tags
    FROM Posts p
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
  ),
  UserQuestionStats AS (
    SELECT
      rq.QuestionId,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation AS OwnerReputation,
      COUNT(DISTINCT ph.PostId) AS NumberOfEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits,
      MAX(ph.CreationDate) AS LastEditDate,
      CASE
        WHEN u.DownVotes > 0 THEN CAST(u.UpVotes AS DOUBLE PRECISION) / u.DownVotes
        ELSE NULL
      END AS UpVoteToDownVoteRatio,
      CASE
        WHEN u.Views > 0 THEN CAST(u.Reputation AS DOUBLE PRECISION) / u.Views
        ELSE NULL
      END AS ReputationPerView
    FROM RecentQuestions rq
    JOIN Users u
      ON rq.OwnerUserId = u.Id
    LEFT JOIN RankedPostEdits ph
      ON rq.QuestionId = ph.PostId AND ph.rn = 1
    GROUP BY
      rq.QuestionId,
      u.DisplayName,
      u.Reputation,
      u.UpVotes,
      u.DownVotes,
      u.Views
  )
SELECT
  rq.QuestionId,
  rq.Title,
  rq.QuestionCreationDate,
  rq.QuestionScore,
  rq.AnswerCount,
  rq.QuestionViewCount,
  rq.QuestionFavoriteCount,
  uqs.OwnerDisplayName,
  uqs.OwnerReputation,
  uqs.NumberOfEdits,
  uqs.BodyEdits,
  uqs.LastEditDate,
  uqs.UpVoteToDownVoteRatio,
  uqs.ReputationPerView,
  COALESCE(ps.TotalPostLinks, 0) AS TotalPostLinks,
  CASE
    WHEN rq.QuestionScore > 100 THEN 'HighScore'
    WHEN rq.QuestionScore > 50 THEN 'MediumScore'
    ELSE 'LowScore'
  END AS ScoreCategory,
  CASE
    WHEN uqs.LastEditDate IS NULL THEN 'NeverEdited'
    WHEN uqs.LastEditDate > rq.QuestionCreationDate + INTERVAL '1 hour' THEN 'EditedLater'
    ELSE 'EditedSoon'
  END AS EditTiming,
  -- extract first tag from Tags string like '<tag1><tag2>'
  NULLIF(
    NULLIF(
      SUBSTRING(rq.Tags FROM 2 FOR POSITION('>' IN rq.Tags)-2),
      ''
    ),
    ''
  ) AS MainTag,
  (
    SELECT
      COUNT(c.Id)
    FROM Comments c
    WHERE
      c.PostId = rq.QuestionId
      AND LENGTH(c.Text) > 100
  ) AS LongCommentCount,
  (
    SELECT
      COUNT(DISTINCT v.UserId)
    FROM Votes v
    WHERE
      v.PostId = rq.QuestionId
      AND v.VoteTypeId = 2
  ) AS UpVoteCount
FROM RecentQuestions rq
LEFT JOIN UserQuestionStats uqs
  ON rq.QuestionId = uqs.QuestionId
LEFT JOIN (
  SELECT
    pl.PostId,
    COUNT(pl.Id) AS TotalPostLinks
  FROM PostLinks pl
  WHERE
    pl.LinkTypeId = 1
  GROUP BY
    pl.PostId
) ps
  ON rq.QuestionId = ps.PostId
WHERE
  rq.question_rank <= 100
  AND (
    uqs.OwnerReputation IS NULL OR uqs.OwnerReputation > 1000
  )
  AND COALESCE(uqs.UpVoteToDownVoteRatio, 1.0) > 0.5
  AND rq.AnswerCount > 0
  AND rq.QuestionViewCount > 100
GROUP BY
  rq.QuestionId,
  rq.Title,
  rq.QuestionCreationDate,
  rq.QuestionScore,
  rq.AnswerCount,
  rq.QuestionViewCount,
  rq.QuestionFavoriteCount,
  uqs.OwnerDisplayName,
  uqs.OwnerReputation,
  uqs.NumberOfEdits,
  uqs.BodyEdits,
  uqs.LastEditDate,
  uqs.UpVoteToDownVoteRatio,
  uqs.ReputationPerView,
  ps.TotalPostLinks,
  rq.QuestionCreationDate + INTERVAL '1 hour',
  rq.Tags,
  rq.question_rank
ORDER BY
  rq.QuestionScore DESC,
  rq.QuestionCreationDate DESC;