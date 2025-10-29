-- {"query": "4142.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1487}
WITH
  RankedAnswers AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.Score,
      p.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
      COUNT(DISTINCT c.Id) AS CommentCount
    FROM Posts AS p
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    WHERE
      p.PostTypeId = 2
    GROUP BY
      p.Id,
      p.ParentId,
      p.OwnerUserId,
      p.Score,
      p.CreationDate
  ),
  UserAnswerStats AS (
    SELECT
      ra.OwnerUserId,
      COUNT(ra.AnswerId) AS TotalAnswers,
      AVG(CAST(ra.Score AS DOUBLE PRECISION)) AS AverageAnswerScore,
      SUM(CASE WHEN ra.rn = 1 THEN 1 ELSE 0 END) AS AcceptedAnswers
    FROM RankedAnswers AS ra
    WHERE
      ra.OwnerUserId IS NOT NULL
    GROUP BY
      ra.OwnerUserId
  ),
  QuestionActivity AS (
    SELECT
      q.Id AS QuestionId,
      q.OwnerUserId AS QuestionOwnerUserId,
      q.Title AS QuestionTitle,
      q.CreationDate AS QuestionCreationDate,
      q.Score AS QuestionScore,
      q.AnswerCount,
      q.ViewCount,
      COUNT(DISTINCT ph.Id) AS PostHistoryEntries,
      MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS LastClosedDate,
      COALESCE(pt.Name, 'Unknown') AS PostTypeName,
      CASE
        WHEN q.Tags IS NULL THEN 'No Tags'
        ELSE REPLACE(REPLACE(q.Tags, '<', ''), '>', ',')
      END AS FormattedTags,
      CASE
        WHEN q.OwnerUserId = -1 THEN 'Community'
        ELSE u.DisplayName
      END AS QuestionOwnerDisplayName,
      CASE
        WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
      END AS Status,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS QuestionUpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS QuestionDownVotes,
      COUNT(DISTINCT q_comments.Id) AS QuestionCommentCount
    FROM Posts AS q
    LEFT JOIN PostHistory AS ph
      ON q.Id = ph.PostId
    LEFT JOIN PostTypes AS pt
      ON q.PostTypeId = pt.Id
    LEFT JOIN Users AS u
      ON q.OwnerUserId = u.Id
    LEFT JOIN Votes AS v
      ON q.Id = v.PostId
    LEFT JOIN Comments AS q_comments
      ON q.Id = q_comments.PostId
    WHERE
      q.PostTypeId = 1
    GROUP BY
      q.Id,
      q.OwnerUserId,
      q.Title,
      q.CreationDate,
      q.Score,
      q.AnswerCount,
      q.ViewCount,
      pt.Name,
      q.Tags,
      q.ClosedDate,
      u.DisplayName
  )
SELECT
  qa.QuestionId,
  qa.QuestionTitle,
  qa.QuestionOwnerDisplayName,
  qa.QuestionScore,
  qa.AnswerCount,
  qa.ViewCount,
  qa.FormattedTags,
  qa.Status,
  qa.QuestionCreationDate,
  ua.TotalAnswers,
  ua.AverageAnswerScore,
  ua.AcceptedAnswers,
  qa.PostHistoryEntries,
  qa.LastClosedDate,
  qa.QuestionUpVotes,
  qa.QuestionDownVotes,
  qa.QuestionCommentCount,
  CASE
    WHEN ua.TotalAnswers IS NULL THEN 0
    ELSE (CAST(ua.AcceptedAnswers AS DOUBLE PRECISION) / ua.TotalAnswers) * 100
  END AS AcceptanceRate,
  CASE
    WHEN qa.QuestionScore > 100 AND qa.AnswerCount > 5 AND qa.ViewCount > 1000 THEN 'High Performance'
    WHEN qa.QuestionScore < 0 THEN 'Low Performance'
    ELSE 'Moderate Performance'
  END AS PerformanceCategory,
  CASE
    WHEN qa.QuestionOwnerUserId = ra.OwnerUserId AND ra.rn = 1 THEN 'Original Poster is Top Answerer'
    ELSE 'Other'
  END AS OwnerRelationship,
  UPPER(SUBSTRING(qa.QuestionTitle FROM 1 FOR 1)) || LOWER(SUBSTRING(qa.QuestionTitle FROM 2 FOR 1000000)) AS FormattedTitle
FROM QuestionActivity AS qa
LEFT JOIN UserAnswerStats AS ua
  ON qa.QuestionOwnerUserId = ua.OwnerUserId
LEFT JOIN RankedAnswers AS ra
  ON qa.QuestionId = ra.QuestionId
WHERE
  qa.QuestionScore > -5
  AND (
    qa.QuestionTitle ILIKE '%performance%'
    OR qa.FormattedTags ILIKE '%sql%'
    OR qa.FormattedTags ILIKE '%database%'
  )
  AND (ua.TotalAnswers IS NULL OR ua.TotalAnswers > 2)
  AND (
    ra.rn <= 3
    OR ra.rn IS NULL
  )
GROUP BY
  qa.QuestionId,
  qa.QuestionTitle,
  qa.QuestionOwnerDisplayName,
  qa.QuestionScore,
  qa.AnswerCount,
  qa.ViewCount,
  qa.FormattedTags,
  qa.Status,
  qa.QuestionCreationDate,
  ua.TotalAnswers,
  ua.AverageAnswerScore,
  ua.AcceptedAnswers,
  qa.PostHistoryEntries,
  qa.LastClosedDate,
  qa.QuestionUpVotes,
  qa.QuestionDownVotes,
  qa.QuestionCommentCount,
  qa.QuestionOwnerUserId,
  ra.OwnerUserId,
  ra.rn
HAVING
  COUNT(DISTINCT qa.QuestionId) > 0
ORDER BY
  qa.QuestionScore DESC,
  qa.ViewCount DESC
LIMIT 100;