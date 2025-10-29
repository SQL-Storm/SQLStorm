-- {"query": "4543.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1370} 

WITH
  -- Calculate total votes for each post, categorizing them by type.
  PostVoteSummary AS (
    SELECT
      PostId,
      COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotes,
      COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotes,
      COUNT(CASE WHEN VoteTypeId = 5 THEN 1 END) AS FavoriteVotes,
      COUNT(CASE WHEN VoteTypeId = 8 THEN 1 END) AS BountyStartVotes,
      SUM(CASE WHEN VoteTypeId = 8 THEN BountyAmount ELSE 0 END) AS TotalBountyAmount
    FROM Votes
    GROUP BY
      PostId
  ),
  -- Identify the most recent edit date and the user who made it for each post.
  LatestPostEdit AS (
    SELECT
      ph.PostId,
      ph.CreationDate AS LastEditDate,
      ph.UserId AS LastEditorUserId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  -- Calculate the average score of answers for each question, excluding posts with no answers.
  AverageAnswerScore AS (
    SELECT
      p.ParentId,
      AVG(CAST(p.Score AS DECIMAL(10, 2))) AS AvgScore
    FROM Posts AS p
    WHERE
      p.PostTypeId = 2 -- Answers
    GROUP BY
      p.ParentId
    HAVING
      COUNT(p.Id) > 0
  ),
  -- Find posts that are linked to other posts as duplicates.
  DuplicateLinks AS (
    SELECT
      pl.RelatedPostId AS DuplicatePostId
    FROM PostLinks AS pl
    WHERE
      pl.LinkTypeId = 3 -- Duplicate
  ),
  -- Combine user information with their total reputation gain from upvotes.
  UserReputationGain AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
      COUNT(b.Id) AS BadgeCount
    FROM Users AS u
    LEFT JOIN Votes AS v
      ON u.Id = v.UserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  )
-- The main query: Selects detailed information about questions, including vote summaries,
-- latest edit details, average answer scores, and links to duplicate questions.
SELECT
  q.Id AS QuestionId,
  q.Title,
  q.CreationDate AS QuestionCreationDate,
  q.Score AS QuestionScore,
  q.AnswerCount,
  q.ViewCount,
  q.FavoriteCount,
  q.ClosedDate,
  pvs.UpVotes AS QuestionUpVotes,
  pvs.DownVotes AS QuestionDownVotes,
  pvs.FavoriteVotes AS QuestionFavoriteVotes,
  pvs.BountyStartVotes AS QuestionBountyStartVotes,
  pvs.TotalBountyAmount AS QuestionTotalBountyAmount,
  COALESCE(las.AvgScore, 0) AS AverageAnswerScore,
  COALESCE(lee.LastEditDate, q.CreationDate) AS LastQuestionEditDate,
  COALESCE(lee.LastEditorUserId, q.OwnerUserId) AS LastQuestionEditorUserId,
  CASE
    WHEN q.OwnerUserId = -1 THEN 'Community'
    ELSE u.DisplayName
  END AS QuestionOwnerDisplayName,
  CASE
    WHEN dl.DuplicatePostId IS NOT NULL THEN 'Yes'
    ELSE 'No'
  END AS IsDuplicate,
  CASE
    WHEN q.Score > (
      SELECT
        AVG(Score)
      FROM Posts
      WHERE
        PostTypeId = 1 AND Score IS NOT NULL
    ) THEN 'Above Average'
    WHEN q.Score < (
      SELECT
        AVG(Score)
      FROM Posts
      WHERE
        PostTypeId = 1 AND Score IS NOT NULL
    ) THEN 'Below Average'
    ELSE 'Average'
  END AS QuestionScoreRank,
  CASE
    WHEN q.OwnerUserId <> -1 AND urg.Reputation > 50000 THEN 'High Reputation User'
    WHEN q.OwnerUserId <> -1 AND urg.Reputation BETWEEN 10000 AND 50000 THEN 'Medium Reputation User'
    ELSE 'Low Reputation User'
  END AS OwnerReputationCategory
FROM Posts AS q
LEFT JOIN PostVoteSummary AS pvs
  ON q.Id = pvs.PostId
LEFT JOIN AverageAnswerScore AS las
  ON q.Id = las.ParentId
LEFT JOIN LatestPostEdit AS lee
  ON q.Id = lee.PostId AND lee.rn = 1
LEFT JOIN Users AS u
  ON q.OwnerUserId = u.Id
LEFT JOIN DuplicateLinks AS dl
  ON q.Id = dl.DuplicatePostId
LEFT JOIN UserReputationGain AS urg
  ON q.OwnerUserId = urg.UserId
WHERE
  q.PostTypeId = 1 -- Questions
  AND q.ClosedDate IS NULL -- Only consider non-closed questions
  AND q.CreationDate >= '2020-01-01' -- Filter for recent questions
  AND (
    q.Title LIKE '%performance%' OR q.Tags LIKE '%performance%'
  ) -- Questions related to 'performance'
  AND q.AnswerCount > 5 -- Questions with more than 5 answers
  AND q.ViewCount > 1000 -- Questions with more than 1000 views
ORDER BY
  q.LastActivityDate DESC,
  q.Score DESC;
