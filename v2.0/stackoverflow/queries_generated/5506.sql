-- {"query": "5506.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 987} 
WITH
-- sample derived dataset to exercise rich features
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.AccountId,
    -- compute a dynamic score based on activity and reputation
    (COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)) * 2
    + COALESCE(vt2.TotalVotes,0)
    + COALESCE(b.TotalBadges,0) AS ActivityScore
  FROM Users u
  LEFT JOIN (
    SELECT UserId, SUM(CASE WHEN VoteTypes.Id IN (2,14) THEN 1 ELSE 0 END) AS TotalVotes
    FROM Votes
    JOIN VoteTypes vt ON vt.Id = Votes.VoteTypeId
    GROUP BY UserId
  ) vt2 ON vt2.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
),
-- top questions with complex filters and window functions
TopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate ASC
    ) AS rn_by_owner
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
    AND p.LastActivityDate > DATEADD(day, -180, CURRENT_DATE)
),
-- correlate recent posts with related posts via PostLinks to exercise self-joins
LinkedPosts AS (
  SELECT
    tl.PostId,
    tl.RelatedPostId,
    pl.LinkTypeId,
    pl.CreationDate AS LinkCreationDate
  FROM PostLinks tl
  JOIN Posts pl ON pl.Id = tl.RelatedPostId
  WHERE tl.LinkTypeId IN (1,3) -- Linked or Duplicate
),
-- compute tag-based popularity from Tags and recent activity
TagPopularity AS (
  SELECT
    t.TagName,
    t.Count AS TagUsage,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.ViewCount) AS MaxViews,
    COUNT(DISTINCT p.Id) AS PostsWithTag
  FROM Tags t
  JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
  WHERE t.TagName IS NOT NULL
  GROUP BY t.TagName, t.Count
),
-- windowed summary of posts per user with NULL-handling in calculations
UserPostSummary AS (
  SELECT
    p.OwnerUserId,
    COUNT(*) AS QuestionsCount,
    SUM(p.Score) AS TotalScore,
    AVG(p.ViewCount) AS AvgViews,
    FIRST_VALUE(p.Title) OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.LastActivityDate DESC
    ) AS MostRecentQuestionTitle,
    MAX(COALESCE(p.LastActivityDate, p.CreationDate)) AS LastActive
  FROM Posts p
  WHERE p.PostTypeId = 1
  GROUP BY p.OwnerUserId
)
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.ActivityScore,
  tq.PostId AS TopQuestionId,
  tq.Title AS TopQuestionTitle,
  tq.Score AS TopQuestionScore,
  tq.ViewCount AS TopQuestionViews,
  tq.CreationDate AS TopQuestionCreated,
  tq.LastActivityDate AS TopQuestionLastActive,
  upm.QuestionsCount,
  upm.TotalScore AS UserTotalScore,
  upm.AvgViews AS UserAvgViews,
  upm.MostRecentQuestionTitle,
  upm.LastActive,
  lp.RelatedPostId AS LinkedPostId,
  lp.LinkTypeId,
  tp.TagName
FROM UserActivity ua
LEFT JOIN TopQuestions tq
  ON tq.OwnerUserId = ua.UserId
LEFT JOIN UserPostSummary upm
  ON upm.OwnerUserId = ua.UserId
LEFT JOIN LinkedPosts lp
  ON lp.PostId = tq.PostId
LEFT JOIN TagPopularity tp
  ON tp.TagName LIKE '%' || regexp_replace(tq.Title, '[^a-zA-Z0-9]', '', 'g') || '%'
WHERE
  ua.ActivityScore > 0
  OR (tq.PostId IS NOT NULL)
ORDER BY ua.ActivityScore DESC NULLS LAST
LIMIT 100;