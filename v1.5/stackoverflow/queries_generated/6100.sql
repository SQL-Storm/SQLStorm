-- {"query": "6100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 860} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  u.Location,
  -- Active participation metric: total posts (questions+answers) by user
  COALESCE(q.TotalQuestions, 0) + COALESCE(a.TotalAnswers, 0) AS TotalPosts_ByUser,
  -- Weighted activity score using multiple dimensions
  COALESCE(q.TotalQuestions, 0) * 3
  + COALESCE(a.TotalAnswers, 0) * 2
  + COALESCE(v.Upvotes, 0) * 0.5
  - COALESCE(v.Downvotes, 0) * 0.25 AS ActivityScore,
  -- Most recent significant action: last edit or last activity
  GREATEST(COALESCE(p.LastEditDate, p.CreationDate), COALESCE(p.LastActivityDate, p.CreationDate)) AS LastActiveDate,
  -- Tags interactions: number of distinct tags in posts by user (simulated via tag names from tags table)
  COUNT(DISTINCT t.TagName) OVER (PARTITION BY u.Id) AS DistinctTagCount,
  -- Complex derived column: string expression combining name and reputation bucket
  CONCAT(u.DisplayName, ' [Rep=', u.Reputation, ']') AS UserLabel,
  -- Example: flag whether user has any Bronze/Silver/Gold badges
  CASE WHEN EXISTS (
        SELECT 1
        FROM Badges b
        WHERE b.UserId = u.Id AND b.Class = 1
      ) THEN 'Has Gold'
       WHEN EXISTS (
        SELECT 1
        FROM Badges b
        WHERE b.UserId = u.Id AND b.Class = 2
      ) THEN 'Has Silver'
       WHEN EXISTS (
        SELECT 1
        FROM Badges b
        WHERE b.UserId = u.Id AND b.Class = 3
      ) THEN 'Has Bronze'
       ELSE 'No Badges'
  END AS BadgeTier
FROM
  Users u
  LEFT JOIN (
    -- total questions per user
    SELECT OwnerUserId, COUNT(*) AS TotalQuestions
    FROM Posts
    WHERE PostTypeId = 1
      AND OwnerUserId IS NOT NULL
      AND ClosedDate IS NULL
    GROUP BY OwnerUserId
  ) q ON q.OwnerUserId = u.Id
  LEFT JOIN (
    -- total answers per user
    SELECT OwnerUserId, COUNT(*) AS TotalAnswers
    FROM Posts
    WHERE PostTypeId = 2
      AND OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
  ) a ON a.OwnerUserId = u.Id
  LEFT JOIN (
    -- votes by user: upvotes and downvotes (simplified)
    SELECT UserId,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Votes
    GROUP BY UserId
  ) v ON v.UserId = u.Id
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN Tags t ON t.Id = pl.RelatedPostId
WHERE
  -- Consider only users with any activity in the dataset to keep results meaningful
  COALESCE(q.TotalQuestions, 0) + COALESCE(a.TotalAnswers, 0) > 0
GROUP BY
  u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location,
  COALESCE(q.TotalQuestions, 0) + COALESCE(a.TotalAnswers, 0),
  COALESCE(v.Upvotes, 0),
  COALESCE(v.Downvotes, 0),
  p.LastEditDate, p.LastActivityDate, u.ProfileImageUrl
ORDER BY
  ActivityScore DESC
LIMIT 100;