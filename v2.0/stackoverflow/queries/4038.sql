-- {"query": "4038.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1094}
WITH
  RankedAnswers AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.Score,
      p.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 2
  ),
  QuestionDetails AS (
    SELECT
      q.Id AS QuestionId,
      q.Title,
      q.CreationDate AS QuestionCreationDate,
      q.OwnerUserId AS QuestionOwnerUserId,
      q.FavoriteCount,
      q.AnswerCount,
      q.ViewCount,
      u.DisplayName AS QuestionOwnerDisplayName,
      u.Reputation AS QuestionOwnerReputation,
      (
        SELECT COUNT(ph.Id)
        FROM PostHistory ph
        WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId IN (4, 6)
      ) AS EditCount,
      COALESCE(
        (
          SELECT COUNT(pl.Id)
          FROM PostLinks pl
          WHERE pl.PostId = q.Id AND pl.LinkTypeId = 3
        ),
        0
      ) AS DuplicateLinkCount
    FROM Posts q
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1
  ),
  UserActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(p.Score) AS TotalScore,
      COUNT(DISTINCT c.Id) AS TotalComments,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.OwnerUserId
  ),
  NetworkStats AS (
    SELECT
      COUNT(DISTINCT Id) AS TotalUsers,
      AVG(Reputation) AS AvgReputation,
      AVG(Views) AS AvgViews
    FROM Users
  )
SELECT
  qd.QuestionId,
  qd.Title,
  qd.QuestionCreationDate,
  qd.QuestionOwnerDisplayName,
  qd.QuestionOwnerReputation,
  qd.FavoriteCount,
  qd.AnswerCount,
  qd.ViewCount,
  qd.EditCount,
  qd.DuplicateLinkCount,
  ra.AnswerId AS BestAnswerId,
  ra.Score AS BestAnswerScore,
  ra.CreationDate AS BestAnswerCreationDate,
  ra.OwnerUserId AS BestAnswerOwnerUserId,
  ua.TotalPosts AS BestAnswerOwnerTotalPosts,
  ua.TotalScore AS BestAnswerOwnerTotalScore,
  ua.TotalComments AS BestAnswerOwnerTotalComments,
  ua.TotalUpVotes AS BestAnswerOwnerTotalUpVotes,
  ua.TotalDownVotes AS BestAnswerOwnerTotalDownVotes,
  CASE
    WHEN ns.TotalUsers > 0 THEN CAST(qd.ViewCount AS DOUBLE PRECISION) / ns.TotalUsers
    ELSE 0
  END AS NormalizedViewCount,
  CASE
    WHEN qd.AnswerCount > 0 THEN CAST(ra.Score AS DOUBLE PRECISION) / qd.AnswerCount
    ELSE 0
  END AS AvgScorePerAnswer,
  CASE
    WHEN qd.QuestionOwnerReputation < 1000 THEN 'Low'
    WHEN qd.QuestionOwnerReputation >= 1000 AND qd.QuestionOwnerReputation < 10000 THEN 'Medium'
    ELSE 'High'
  END AS OwnerReputationLevel,
  CASE
    WHEN qd.QuestionCreationDate < (cast('2024-10-01' as date) - INTERVAL '1 year') THEN 'Old'
    ELSE 'Recent'
  END AS QuestionAgeCategory
FROM QuestionDetails qd
LEFT JOIN RankedAnswers ra ON qd.QuestionId = ra.QuestionId AND ra.rn = 1
LEFT JOIN UserActivity ua ON ra.OwnerUserId = ua.OwnerUserId
LEFT JOIN NetworkStats ns ON 1 = 1
WHERE
  qd.QuestionOwnerReputation > 100
  AND qd.FavoriteCount > 0
  AND qd.AnswerCount BETWEEN 1 AND 10
  AND qd.Title LIKE '%SQL%'
  AND qd.QuestionOwnerDisplayName IS NOT NULL
ORDER BY
  qd.ViewCount DESC
LIMIT 100;