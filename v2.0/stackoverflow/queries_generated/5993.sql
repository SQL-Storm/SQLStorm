-- {"query": "5993.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 829} 
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.PostTypeId,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS UserDisplayName,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS UserLastAccessDate,
    b.Name AS BadgeName,
    b.Date AS BadgeDate,
    b.Class AS BadgeClass,
    b.TagBased AS BadgeTagBased,
    t.Count AS TagCount,
    v.UpModCount,
    v.DownModCount,
    v.TotalVotes
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT UserId, MAX(Name) AS Name, MAX(Date) AS Date, MAX(Class) AS Class, MAX(TagBased) AS TagBased
    FROM Badges
    GROUP BY UserId
  ) AS b ON p.OwnerUserId = b.UserId
  LEFT JOIN (
    SELECT TagName, SUM(Count) AS Count
    FROM Tags
    GROUP BY TagName
  ) AS t ON t.TagName LIKE '%' || p.Title || '%'
  LEFT JOIN (
    SELECT
      p.OwnerUserId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpModCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownModCount,
      COUNT(*) AS TotalVotes
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
  ) AS v ON p.OwnerUserId = v.OwnerUserId
  WHERE p.PostTypeId IN (1, 2) -- questions and answers
),
Filtered AS (
  SELECT
    RP.*,
    ROW_NUMBER() OVER (
      PARTITION BY RP.OwnerUserId
      ORDER BY RP.CreationDate DESC
    ) AS rn_by_user
  FROM RankedPosts RP
  WHERE RP.Reputation IS NOT NULL
    AND RP.BadgeName IS NOT NULL
    AND RP.TagCount > 0
),
Joined AS (
  SELECT
    F.*
  FROM Filtered F
  LEFT JOIN LATERAL (
    SELECT 1
  ) AS Dummy ON TRUE
)
SELECT
  J.PostId,
  J.Title,
  J.Tags,
  J.Score,
  J.ViewCount,
  J.CreationDate,
  J.LastActivityDate,
  J.OwnerUserId,
  J.OwnerDisplayName,
  J.PostTypeId,
  J.CommentCount,
  J.AnswerCount,
  J.FavoriteCount,
  J.ContentLicense,
  J.Reputation,
  J.UserDisplayName,
  J.UserCreationDate,
  J.UserLastAccessDate,
  J.BadgeName,
  J.BadgeDate,
  J.BadgeClass,
  J.BadgeTagBased,
  J.TagCount,
  J.UpModCount,
  J.DownModCount,
  J.TotalVotes,
  DATE_TRUNC('hour', J.CreationDate) AS CreationHour,
  CASE
    WHEN J.Reputation >= 2000 THEN 'High'
    WHEN J.Reputation >= 1000 THEN 'Medium'
    ELSE 'Low'
  END AS ReputationBand,
  (SELECT MAX(CreationDate) FROM Votes WHERE PostId = J.PostId) AS LastVoteDate,
  (SELECT STRING_AGG(CONCAT('v', VoteTypeId, ':', BountyAmount), ',') FROM Votes v WHERE v.PostId = J.PostId) AS VoteSummary
FROM Joined J
ORDER BY J.LastActivityDate DESC
LIMIT 100;