-- {"query": "4428.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1384}
WITH
  QuestionDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.ViewCount AS QuestionViewCount,
      p.AnswerCount AS QuestionAnswerCount,
      p.FavoriteCount AS QuestionFavoriteCount,
      p.Tags AS QuestionTags,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
      END AS QuestionStatus,
      p.OwnerUserId AS OwnerUserId,
      COUNT(c.Id) AS CommentCount,
      ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS rn_post
    FROM Posts AS p
    LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.Id,
      p.Title,
      u.DisplayName,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      p.Tags,
      p.OwnerUserId,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
      END
  ),
  AnswerSummary AS (
    SELECT
      p.ParentId AS QuestionId,
      COUNT(p.Id) AS TotalAnswers,
      SUM(CASE WHEN q.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
      AVG(CAST(p.Score AS NUMERIC(10,2))) AS AverageAnswerScore,
      SUM(CASE WHEN p.OwnerUserId = q.OwnerUserId THEN 1 ELSE 0 END) AS AnswersByQuestionOwner
    FROM Posts AS p
    JOIN Posts AS q
      ON p.ParentId = q.Id
    WHERE
      p.PostTypeId = 2
    GROUP BY
      p.ParentId
  ),
  TagStats AS (
    SELECT
      pt.Id AS PostId,
      COUNT(t.Id) AS NumberOfTags,
      -- Use a standard string aggregation function name; many dialects support LISTAGG or STRING_AGG.
      -- Use STRING_AGG for compatibility; if not available in target dialect, replace with appropriate func.
      STRING_AGG(t.TagName, ',') AS TagList
    FROM Posts AS pt
    JOIN Tags AS t
      ON POSITION(t.TagName IN REPLACE(REPLACE(pt.Tags, '<', ''), '>', '')) > 0
    WHERE
      pt.PostTypeId = 1
    GROUP BY
      pt.Id
  ),
  UserActivity AS (
    SELECT
      UserId,
      COUNT(Id) AS TotalVotes,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    WHERE
      UserId IS NOT NULL
    GROUP BY
      UserId
  ),
  MostRecentEdit AS (
    SELECT
      PostId,
      MAX(CreationDate) AS LastEditDate
    FROM PostHistory
    WHERE
      PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    GROUP BY
      PostId
  )
SELECT
  q.QuestionId,
  q.QuestionTitle,
  q.OwnerDisplayName,
  q.QuestionCreationDate,
  q.QuestionScore,
  q.QuestionViewCount,
  q.QuestionFavoriteCount,
  q.QuestionAnswerCount,
  q.QuestionStatus,
  COALESCE(q.CommentCount, 0) AS TotalComments,
  COALESCE(ans.TotalAnswers, 0) AS TotalAnswers,
  COALESCE(ans.AcceptedAnswerCount, 0) AS AcceptedAnswerCount,
  ans.AverageAnswerScore,
  ans.AnswersByQuestionOwner,
  ts.NumberOfTags,
  ts.TagList,
  CASE
    WHEN q.OwnerUserId IS NOT NULL THEN u.Reputation
    ELSE NULL
  END AS OwnerReputation,
  ua.TotalVotes AS VoterTotalVotes,
  ua.UpVotes AS VoterUpVotes,
  ua.DownVotes AS VoterDownVotes,
  mer.LastEditDate AS PostLastEditDate,
  CASE
    WHEN q.QuestionScore < 0 THEN 'Negative Score'
    WHEN q.QuestionScore BETWEEN 0 AND 10 THEN 'Low Score'
    WHEN q.QuestionScore BETWEEN 11 AND 100 THEN 'Medium Score'
    ELSE 'High Score'
  END AS ScoreCategory,
  UPPER(SUBSTRING(q.QuestionTitle FROM 1 FOR 3)) AS TitleInitialCaps,
  EXTRACT(YEAR FROM q.QuestionCreationDate) AS QuestionYear,
  CASE
    WHEN q.QuestionTags LIKE '%<sql>%' THEN 'Contains SQL'
    ELSE 'Does not contain SQL'
  END AS ContainsSqlTag,
  COALESCE(
    (
      SELECT
        COUNT(*)
      FROM PostLinks AS pl
      WHERE
        pl.PostId = q.QuestionId AND pl.LinkTypeId = 3
    ),
    0
  ) AS DuplicateLinks
FROM QuestionDetails AS q
LEFT JOIN AnswerSummary AS ans
  ON q.QuestionId = ans.QuestionId
LEFT JOIN TagStats AS ts
  ON q.QuestionId = ts.PostId
LEFT JOIN Users AS u
  ON q.OwnerUserId = u.Id
LEFT JOIN UserActivity AS ua
  ON q.OwnerUserId = ua.UserId
LEFT JOIN MostRecentEdit AS mer
  ON q.QuestionId = mer.PostId
WHERE
  q.QuestionViewCount > 1000
  AND q.QuestionScore > 5
  AND q.QuestionCreationDate BETWEEN DATE '2020-01-01' AND DATE '2023-12-31'
  AND (
    q.OwnerDisplayName IS NOT NULL OR q.OwnerUserId IS NULL
  )
  AND q.QuestionTitle IS NOT NULL
ORDER BY
  q.QuestionScore DESC,
  q.QuestionCreationDate ASC
LIMIT 100;