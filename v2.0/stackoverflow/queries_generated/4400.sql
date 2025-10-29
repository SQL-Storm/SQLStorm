-- {"query": "4400.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 966} 

WITH
  RankedQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      COUNT(a.Id) AS AnswerCount,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.OwnerUserId
        ORDER BY
          p.CreationDate DESC
      ) AS rn
    FROM Posts AS p
    LEFT JOIN Posts AS a
      ON p.Id = a.ParentId
    WHERE
      p.PostTypeId = 1 -- Questions
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.Title
  ),
  UserPostActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5) THEN ph.CreationDate ELSE NULL END) AS LastPostEditDate,
      COUNT(DISTINCT ph.PostId) AS PostsEditedCount,
      SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVotesCast,
      SUM(CASE WHEN ph.PostHistoryTypeId = 16 THEN 1 ELSE 0 END) AS CommunityOwnedEvents,
      CASE
        WHEN u.WebsiteUrl IS NULL THEN 'No Website'
        WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
        ELSE 'External Website'
      END AS WebsiteCategory
    FROM Users AS u
    LEFT JOIN PostHistory AS ph
      ON u.Id = ph.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.WebsiteUrl
  )
SELECT
  rq.QuestionId,
  rq.QuestionTitle,
  rq.QuestionCreationDate,
  rq.QuestionScore,
  rq.AnswerCount,
  upa.DisplayName AS QuestionOwnerDisplayName,
  upa.Reputation AS QuestionOwnerReputation,
  upa.UserCreationDate AS QuestionOwnerCreationDate,
  upa.LastPostEditDate,
  upa.PostsEditedCount,
  upa.CloseVotesCast,
  upa.CommunityOwnedEvents,
  upa.WebsiteCategory,
  COALESCE(u_edit.DisplayName, 'Unknown') AS LastEditorDisplayName,
  p.LastEditDate,
  p.ViewCount,
  p.FavoriteCount,
  p.Tags,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = p.Id AND c.Score > 0
  ) AS PositiveCommentCount,
  (
    SELECT
      COUNT(*)
    FROM Votes AS v
    WHERE
      v.PostId = p.Id AND v.VoteTypeId = 2 -- Upvotes
  ) AS UpVoteCount,
  RANK() OVER (
    ORDER BY
      rq.QuestionScore DESC,
      rq.AnswerCount DESC
  ) AS QuestionRank
FROM RankedQuestions AS rq
JOIN Posts AS p
  ON rq.QuestionId = p.Id
JOIN UserPostActivity AS upa
  ON rq.OwnerUserId = upa.UserId
LEFT JOIN Users AS u_edit
  ON p.LastEditorUserId = u_edit.Id
WHERE
  rq.rn = 1 -- Only consider the most recent question for each user
  AND p.Score > 10 -- Filter for questions with at least some engagement
  AND LENGTH(p.Tags) > 5 -- Filter for questions with tags
  AND p.Title IS NOT NULL
  AND SUBSTRING(p.Body, 1, 100) <> SUBSTRING(p.Body, LENGTH(p.Body) - 99, 100) -- Crude check for non-trivial body
ORDER BY
  QuestionRank
LIMIT 50;
