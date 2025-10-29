-- {"query": "4334.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 737}
WITH
  UserPostCounts AS (
    SELECT
      OwnerUserId,
      COUNT(Id) AS TotalPosts
    FROM
      Posts
    WHERE
      OwnerUserId IS NOT NULL
    GROUP BY
      OwnerUserId
  ),
  HighReputationUsers AS (
    SELECT
      Id
    FROM
      Users
    WHERE
      Reputation > 10000
  ),
  RecentQuestions AS (
    SELECT
      Id,
      OwnerUserId,
      Title,
      Tags,
      CreationDate,
      AnswerCount,
      Score,
      ROW_NUMBER() OVER (ORDER BY CreationDate DESC) AS rn
    FROM
      Posts
    WHERE
      PostTypeId = 1
      AND CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30 days')
  ),
  TopAnswers AS (
    SELECT
      p.Id,
      p.OwnerUserId,
      p.ParentId,
      p.Score,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) AS answer_rank
    FROM
      Posts p
    WHERE
      p.PostTypeId = 2
  )
SELECT
  u.DisplayName AS UserName,
  upc.TotalPosts,
  (
    SELECT
      COUNT(*)
    FROM
      Badges b
    WHERE
      b.UserId = u.Id AND b.Class = 1
  ) AS GoldBadges,
  CASE WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus,
  COUNT(DISTINCT rq.Id) AS RecentQuestionsCount,
  AVG(ta.Score) AS AverageTopAnswerScore,
  SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPostsCount,
  CONCAT(
    u.DisplayName,
    ' - ',
    COALESCE(u.Location, 'Unknown Location')
  ) AS UserLocationInfo,
  COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5)) AS EditsMade
FROM
  Users u
LEFT OUTER JOIN
  UserPostCounts upc
  ON u.Id = upc.OwnerUserId
LEFT OUTER JOIN
  RecentQuestions rq
  ON u.Id = rq.OwnerUserId AND rq.rn <= 5
LEFT OUTER JOIN
  TopAnswers ta
  ON u.Id = ta.OwnerUserId AND ta.answer_rank = 1
LEFT OUTER JOIN
  Posts p
  ON u.Id = p.OwnerUserId
LEFT OUTER JOIN
  PostHistory ph
  ON u.Id = ph.UserId
WHERE
  u.Id IN (SELECT Id FROM HighReputationUsers)
  AND u.Id NOT IN (SELECT UserId FROM Votes WHERE VoteTypeId = 3)
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.WebsiteUrl,
  u.Location,
  upc.TotalPosts
HAVING
  COUNT(DISTINCT rq.Id) > 0 OR AVG(ta.Score) IS NOT NULL
ORDER BY
  u.Reputation DESC,
  u.CreationDate ASC;