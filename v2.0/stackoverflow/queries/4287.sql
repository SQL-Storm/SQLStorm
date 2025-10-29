-- {"query": "4287.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1294}
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      u.DisplayName AS EditorDisplayName,
      ph.CreationDate AS EditDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN Users u
      ON ph.UserId = u.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
  ),
  UserActivitySummary AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      MAX(u.Reputation) AS MaxReputation,
      MAX(u.Reputation) AS Reputation
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c
      ON u.Id = c.UserId
    LEFT JOIN Votes v
      ON u.Id = v.UserId
    WHERE
      u.CreationDate > DATE '2010-01-01'
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  TagStats AS (
    SELECT
      t.TagName,
      COUNT(DISTINCT p.Id) AS TotalQuestions,
      AVG(CAST(p.AnswerCount AS DECIMAL)) AS AvgAnswerCount,
      SUM(p.FavoriteCount) AS TotalFavorites
    FROM Tags t
    JOIN Posts p
      ON p.Id = t.WikiPostId
    WHERE
      t.TagName NOT LIKE '#%'
    GROUP BY
      t.TagName
  )
SELECT
  p.Id AS PostId,
  pt.Name AS PostType,
  p.Title,
  u.DisplayName AS OwnerDisplayName,
  ua.Reputation AS OwnerReputation,
  ua.UpVoteCount AS OwnerUpVotes,
  COALESCE(p.Score, 0) AS PostScore,
  COALESCE(p.ViewCount, 0) AS PostViewCount,
  p.CreationDate AS PostCreationDate,
  p.LastActivityDate AS PostLastActivityDate,
  (
    SELECT
      COUNT(*)
    FROM Comments c
    WHERE
      c.PostId = p.Id
      AND c.CreationDate > (p.CreationDate - INTERVAL '1' HOUR)
  ) AS CommentsPerHourOfPostCreation,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  COALESCE(p.AnswerCount, 0) AS TotalAnswers,
  (
    SELECT
      COUNT(*)
    FROM PostLinks pl
    WHERE
      pl.PostId = p.Id AND pl.LinkTypeId = 3
  ) AS DuplicateLinks,
  LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
  SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningScoreSum,
  ts.TagName,
  ts.TotalQuestions AS TagTotalQuestions,
  ts.AvgAnswerCount AS TagAvgAnswers,
  rp.EditDate AS LastEditDateByOwner,
  CASE
    WHEN rp.UserId = p.OwnerUserId THEN 'Owner Edited'
    ELSE 'SomeoneElseEdited'
  END AS EditOrigin,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM Votes v
      WHERE
        v.PostId = p.Id AND v.VoteTypeId = 2 AND v.UserId = p.OwnerUserId
    ) THEN 'OwnerUpvoted'
    ELSE 'OwnerDidNotUpvote'
  END AS OwnerVoteStatus
FROM Posts p
JOIN PostTypes pt
  ON p.PostTypeId = pt.Id
LEFT JOIN Users u
  ON p.OwnerUserId = u.Id
LEFT JOIN UserActivitySummary ua
  ON u.Id = ua.UserId
LEFT JOIN RankedPostEdits rp
  ON p.Id = rp.PostId AND rp.rn = 1
LEFT JOIN TagStats ts
  ON EXISTS (
    SELECT 1
    FROM (
      SELECT TRIM(value) AS val
      FROM (
        SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2)), '><')) AS value
      ) AS derived_inner
    ) AS derived_vals
    WHERE derived_vals.val = ts.TagName
  )
WHERE
  p.PostTypeId IN (1, 2)
  AND p.Score > 10
  AND EXISTS (
    SELECT
      1
    FROM Comments c
    WHERE
      c.PostId = p.Id AND c.Text LIKE '%interesting%'
  )
  AND ua.MaxReputation BETWEEN 1000 AND 50000
GROUP BY
  p.Id,
  pt.Name,
  p.Title,
  u.DisplayName,
  ua.Reputation,
  ua.UpVoteCount,
  COALESCE(p.Score, 0),
  COALESCE(p.ViewCount, 0),
  p.CreationDate,
  p.LastActivityDate,
  ts.TagName,
  ts.TotalQuestions,
  ts.AvgAnswerCount,
  rp.EditDate,
  rp.UserId,
  p.ClosedDate,
  p.CommunityOwnedDate,
  COALESCE(p.AnswerCount, 0),
  p.OwnerUserId
ORDER BY
  p.LastActivityDate DESC
LIMIT 1000;