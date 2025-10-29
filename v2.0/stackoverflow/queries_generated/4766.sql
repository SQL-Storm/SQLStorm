-- {"query": "4766.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1581} 

WITH
  -- Calculate a 'quality score' for each post based on its type and score.
  PostQuality AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.Score,
      CASE
        WHEN p.PostTypeId = 1 THEN p.Score * 1.5 -- Questions with higher scores are more valuable
        WHEN p.PostTypeId = 2 THEN p.Score * 1.2 -- Answers with higher scores are valuable
        WHEN p.PostTypeId IN (3, 5) THEN p.Score * 1.1 -- Wiki content with higher scores is valuable
        ELSE p.Score
      END AS CalculatedQuality,
      p.OwnerUserId,
      p.CreationDate,
      p.Title,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      pt.Name AS PostTypeName
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.Score > 0 OR p.PostTypeId IN (3, 5) -- Focus on posts with some engagement or wiki content
  ),
  -- Rank users based on their overall contribution (Reputation and number of badges).
  UserContributionRank AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(b.Id) AS BadgeCount,
      RANK() OVER (ORDER BY u.Reputation DESC, COUNT(b.Id) DESC) AS UserRank
    FROM Users AS u
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
    HAVING
      u.Reputation > 1000 -- Consider users with a significant reputation
  ),
  -- Identify posts that have been closed, possibly with a reason and date.
  ClosedPostsInfo AS (
    SELECT
      p.Id AS PostId,
      p.ClosedDate,
      crt.Name AS CloseReasonName
    FROM Posts AS p
    LEFT JOIN PostHistory AS ph
      ON p.Id = ph.PostId
    LEFT JOIN CloseReasonTypes AS crt
      ON TRY_CAST(ph.Comment AS INT) = crt.Id -- The 'Comment' field stores CloseReasonId for PostHistoryTypeId 10
    WHERE
      p.ClosedDate IS NOT NULL
      AND ph.PostHistoryTypeId = 10 -- Post Closed event
  ),
  -- Calculate the average 'quality score' of questions answered by each user, considering only accepted answers.
  UserAnswerQuality AS (
    SELECT
      p_ans.OwnerUserId,
      AVG(pq.CalculatedQuality) AS AvgAcceptedAnswerQuality,
      COUNT(DISTINCT p_q.Id) AS NumberOfQuestionsAnswered
    FROM Posts AS p_ans
    JOIN Posts AS p_q
      ON p_ans.ParentId = p_q.Id -- p_ans is an answer, p_q is the question
    JOIN PostQuality AS pq
      ON p_ans.Id = pq.PostId
    WHERE
      p_ans.PostTypeId = 2 -- Ensure p_ans is an answer
      AND p_q.AcceptedAnswerId = p_ans.Id -- Only consider accepted answers
      AND p_ans.OwnerUserId IS NOT NULL
    GROUP BY
      p_ans.OwnerUserId
  ),
  -- Aggregate post metrics for each post type.
  PostTypeMetrics AS (
    SELECT
      pt.Name AS PostTypeName,
      COUNT(p.Id) AS TotalPosts,
      AVG(p.Score) AS AvgScore,
      SUM(p.ViewCount) AS TotalViews,
      AVG(p.AnswerCount) AS AvgAnswers
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    GROUP BY
      pt.Name
  )
-- Final query combining various metrics to analyze post performance and user impact.
SELECT
  pq.PostId,
  pq.Title,
  pq.PostTypeName,
  pq.CalculatedQuality,
  pq.Score,
  pq.FavoriteCount,
  pq.CommentCount,
  pq.AnswerCount,
  u.DisplayName AS OwnerDisplayName,
  ucr.UserRank,
  COALESCE(cpi.CloseReasonName, 'Not Closed') AS ClosureStatus,
  CASE
    WHEN cpi.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END AS IsPostClosed,
  uaq.AvgAcceptedAnswerQuality,
  uaq.NumberOfQuestionsAnswered,
  ptm.TotalPosts AS PostTypeTotalPosts,
  ptm.AvgScore AS PostTypeAvgScore,
  ptm.TotalViews AS PostTypeTotalViews,
  ptm.AvgAnswers AS PostTypeAvgAnswers,
  -- A complex calculation: adjust quality by user rank and average answer quality for questions.
  CASE
    WHEN pq.PostTypeId = 1 THEN pq.CalculatedQuality * (1.0 / ucr.UserRank) * COALESCE(uaq.AvgAcceptedAnswerQuality, 0)
    ELSE pq.CalculatedQuality * (1.0 / ucr.UserRank)
  END AS AdjustedQualityScore,
  -- Check for posts with unusual engagement patterns (e.g., high comments vs. low score)
  CASE
    WHEN pq.Score < 5 AND pq.CommentCount > 10 THEN 'High Comment/Low Score Anomaly'
    WHEN pq.Score > 50 AND pq.CommentCount < 5 THEN 'High Score/Low Comment Anomaly'
    ELSE 'Normal Engagement'
  END AS EngagementPattern,
  -- Concatenate tag names with a separator, handling potential NULLs and empty strings.
  REPLACE(REPLACE(pq.Tags, '<', ''), '>', '') AS FormattedTags
FROM PostQuality AS pq
LEFT JOIN Users AS u
  ON pq.OwnerUserId = u.Id
LEFT JOIN UserContributionRank AS ucr
  ON u.Id = ucr.UserId
LEFT JOIN ClosedPostsInfo AS cpi
  ON pq.PostId = cpi.PostId
LEFT JOIN UserAnswerQuality AS uaq
  ON pq.OwnerUserId = uaq.OwnerUserId AND pq.PostTypeId = 1 -- Link user answer quality only for questions
LEFT JOIN PostTypeMetrics AS ptm
  ON pq.PostTypeName = ptm.PostTypeName
WHERE
  pq.CreationDate BETWEEN '2020-01-01' AND '2023-12-31' -- Filter by date range
  AND (pq.Score > 10 OR pq.PostTypeName = 'Question') -- Focus on higher scoring posts or questions
  AND u.Id IS NOT NULL -- Ensure the owner user exists
ORDER BY
  AdjustedQualityScore DESC
LIMIT 100; -- Limit results for performance
