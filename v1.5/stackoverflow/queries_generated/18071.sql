-- {"query": "18071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 965} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserContributionSummary AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
      COUNT(DISTINCT b.Id) AS BadgesEarned,
      MAX(u.Reputation) AS MaxReputation
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  TagPopularity AS (
    SELECT
      t.TagName,
      COUNT(DISTINCT p.Id) AS PostsWithTag,
      AVG(p.Score) AS AverageTagScore,
      SUM(CASE WHEN p.OwnerUserId IS NOT NULL AND p.OwnerUserId != -1 THEN 1 ELSE 0 END) AS UserOwnedTagPosts
    FROM Tags AS t
    JOIN Posts AS p
      ON t.Id = SUBSTRING(p.Tags, 2, CHARINDEX('>', p.Tags) - 2) -- Basic tag parsing assumption
    WHERE
      p.PostTypeId = 1 -- Only consider questions for tag popularity
    GROUP BY
      t.TagName
  ),
  RecentQuestions AS (
    SELECT
      Id,
      Title,
      OwnerUserId,
      AcceptedAnswerId,
      AnswerCount,
      CreationDate,
      Score,
      DENSE_RANK() OVER (ORDER BY Score DESC, AnswerCount DESC) AS QuestionRank
    FROM Posts
    WHERE
      PostTypeId = 1 AND CreationDate >= DATEADD(month, -3, GETDATE())
  )
SELECT
  rq.Title AS RecentQuestionTitle,
  ucs.DisplayName AS QuestionOwner,
  COALESCE(rq.AnswerCount, 0) AS AnswerCount,
  COALESCE(rpe.PostHistoryTypeId, 0) AS LastEditType,
  tp.TagName,
  tp.AverageTagScore,
  COALESCE(ucs.BadgesEarned, 0) AS OwnerBadges,
  COALESCE(ucs.MaxReputation, 0) AS OwnerMaxReputation,
  CASE
    WHEN tp.UserOwnedTagPosts > tp.PostsWithTag * 0.7 THEN 'Community Dominant'
    WHEN tp.UserOwnedTagPosts < tp.PostsWithTag * 0.3 THEN 'User Dominant'
    ELSE 'Mixed Dominance'
  END AS TagOwnershipStyle
FROM RecentQuestions AS rq
JOIN UserContributionSummary AS ucs
  ON rq.OwnerUserId = ucs.UserId
LEFT JOIN RankedPostEdits AS rpe
  ON rq.Id = rpe.PostId AND rpe.rn = 1 -- Get the most recent edit for each post
LEFT JOIN TagPopularity AS tp
  ON SUBSTRING(rq.Tags, 2, CHARINDEX('>', rq.Tags) - 2) = tp.TagName -- Basic tag parsing
WHERE
  rq.QuestionRank <= 100 -- Top 100 recent questions by score/answer count
  AND ucs.TotalPosts > 10 -- Users with more than 10 posts
  AND tp.PostsWithTag > 50 -- Tags with more than 50 questions
UNION ALL
SELECT
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL
FROM Posts AS p
WHERE
  p.Id < 0; -- Dummy to ensure union returns correct number of columns if first part is empty.
