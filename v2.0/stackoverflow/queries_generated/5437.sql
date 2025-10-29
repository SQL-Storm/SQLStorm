-- {"query": "5437.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 776} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  COALESCE(u.Location, '') AS Location,
  COALESCE(u.AboutMe, '') AS AboutMe,
  COALESCE(u.Views, 0) AS Views,
  COALESCE(u.UpVotes, 0) AS UpVotes,
  COALESCE(u.DownVotes, 0) AS DownVotes,
  COALESCE(u.ProfileImageUrl, '') AS ProfileImageUrl,
  COALESCE(u.EmailHash, '') AS EmailHash,
  COALESCE(u.AccountId, 0) AS AccountId,
  b.GoldCount,
  b.SilverCount,
  b.BronzeCount,
  COALESCE(p.QuestionCount, 0) AS QuestionCount,
  COALESCE(p.AnswerCount, 0) AS AnswerCount,
  COALESCE(vt.TotalUpvotes, 0) AS TotalUpvotesOnUserPosts,
  COALESCE(vt.TotalDownvotesOnUserPosts, 0) AS TotalDownvotesOnUserPosts,
  STRING_AGG(DISTINCT t.TagName, ',') AS TagNames,
  MAX(p2.LastActivityDate) OVER (PARTITION BY u.Id) AS LastActivityForUser
FROM
  Users u
LEFT JOIN (
  SELECT
    UserId,
    COUNT(*) AS GoldCount
  FROM Badges
  WHERE Class = 1
  GROUP BY UserId
) b ON b.UserId = u.Id
LEFT JOIN (
  SELECT
    OwnerUserId AS UserId,
    COUNT(*) AS QuestionCount
  FROM Posts
  WHERE PostTypeId = 1
  GROUP BY OwnerUserId
) p ON p.UserId = u.Id
LEFT JOIN (
  SELECT
    OwnerUserId AS UserId,
    COUNT(*) AS AnswerCount
  FROM Posts
  WHERE PostTypeId = 2
  GROUP BY OwnerUserId
) p2 ON p2.UserId = u.Id
LEFT JOIN (
  SELECT
    UserId,
    SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
    SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes
  FROM Votes
  GROUP BY UserId
) vt ON vt.UserId = u.Id
LEFT JOIN (
  SELECT
    OwnerUserId AS UserId,
    STRING_AGG(TagName, ',') AS TagNames
  FROM (
    SELECT
      p.OwnerUserId,
      t.TagName
    FROM Posts p
    JOIN Tags t ON t.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
  ) s
  GROUP BY UserId
) t ON t.UserId = u.Id
LEFT JOIN Posts p3 ON p3.OwnerUserId = u.Id
  AND p3.PostTypeId = 1
LEFT JOIN Posts p4 ON p4.OwnerUserId = u.Id
  AND p4.PostTypeId = 2
WINDOW w AS ()
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  u.Location,
  u.AboutMe,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  u.ProfileImageUrl,
  u.EmailHash,
  u.AccountId,
  b.GoldCount,
  b.SilverCount,
  b.BronzeCount,
  p.QuestionCount,
  p.AnswerCount,
  vt.TotalUpvotes,
  vt.TotalDownvotes;