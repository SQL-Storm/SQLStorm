-- {"query": "5985.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 995}
WITH
RecentActivePosts AS (
  SELECT p.Id,
         p.PostTypeId,
         p.OwnerUserId,
         p.Title,
         p.Tags,
         p.CreationDate,
         p.LastActivityDate,
         p.Score,
         p.ViewCount,
         p.CommentCount,
         p.AnswerCount,
         p.FavoriteCount,
         p.ParentId,
         p.AcceptedAnswerId
  FROM Posts p
  WHERE p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '90' DAY
),
TagRef AS (
  SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
         p.Id AS PostId
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TopTags AS (
  SELECT t.TagName,
         COUNT(*) AS TagCount,
         AVG(p.Score) AS AvgScore,
         MAX(p.LastActivityDate) AS LastActive
  FROM TagRef t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.TagName
  ORDER BY TagCount DESC
  LIMIT 20
),
UserStats AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.AccountId,
         u.CreationDate,
         u.LastAccessDate,
         u.Location,
         u.Views,
         u.UpVotes,
         u.DownVotes,
         (SELECT COUNT(*) FROM Posts pr WHERE pr.OwnerUserId = u.Id AND pr.PostTypeId = 1 AND pr.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365' DAY) AS QuestionsLastYear,
         (SELECT COUNT(*) FROM Posts pr WHERE pr.OwnerUserId = u.Id AND pr.PostTypeId = 2 AND pr.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365' DAY) AS AnswersLastYear
  FROM Users u
  WHERE u.AccountId IS NOT NULL
),
UserBadges AS (
  SELECT b.UserId,
         b.Name AS BadgeName,
         b.Class,
         b.Date
  FROM Badges b
  WHERE b.Date >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR
),
CorrelatedVotes AS (
  SELECT v.PostId,
         v.VoteTypeId,
         v.UserId,
         v.CreationDate,
         v.BountyAmount,
         CASE
           WHEN v.VoteTypeId IN (2,3) THEN 'Up/Down'
           WHEN v.VoteTypeId = 6 THEN 'Close'
           WHEN v.VoteTypeId = 8 THEN 'BountyStart'
           WHEN v.VoteTypeId = 9 THEN 'BountyClose'
           ELSE 'Other'
         END AS VoteCategory
  FROM Votes v
  WHERE v.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180' DAY
),
OpenClosedSummary AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.ClosedDate,
    p.CreationDate,
    (CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END) AS Status,
    COUNT(CASE WHEN v.VoteTypeId = 10 THEN 1 END) AS DeletionVotes
  FROM Posts p
  LEFT JOIN Posts qp ON qp.Id = p.ParentId
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.Id, p.PostTypeId, p.ClosedDate, p.CreationDate
)
SELECT
  rp.Id AS PostId,
  rp.PostTypeId,
  rp.Title,
  rp.Tags,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.Score,
  rp.ViewCount,
  rp.CommentCount,
  rp.AnswerCount,
  rp.FavoriteCount,
  ua.UserId AS AuthorUserId,
  ua.DisplayName AS AuthorDisplayName,
  ua.Reputation,
  ua.LastAccessDate,
  ua.Location,
  ua.QuestionsLastYear,
  ua.AnswersLastYear,
  uw.BadgeName AS LatestBadge,
  uw.Class AS BadgeClass,
  uw.Date AS BadgeDate,
  ct.TagName,
  ct.TagCount,
  ct.AvgScore AS TagAvgScore,
  ct.LastActive AS TagLastActive,
  cv.VoteTypeId,
  cv.VoteCategory,
  os.Status AS PostStatus,
  os.DeletionVotes
FROM RecentActivePosts rp
LEFT JOIN UserStats ua ON ua.UserId = rp.OwnerUserId
LEFT JOIN UserBadges uw ON uw.UserId = rp.OwnerUserId
LEFT JOIN TopTags ct ON TRUE
LEFT JOIN CorrelatedVotes cv ON cv.PostId = rp.Id
LEFT JOIN OpenClosedSummary os ON os.PostId = rp.Id
GROUP BY
  rp.Id,
  rp.PostTypeId,
  rp.Title,
  rp.Tags,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.Score,
  rp.ViewCount,
  rp.CommentCount,
  rp.AnswerCount,
  rp.FavoriteCount,
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.LastAccessDate,
  ua.Location,
  ua.QuestionsLastYear,
  ua.AnswersLastYear,
  uw.BadgeName,
  uw.Class,
  uw.Date,
  ct.TagName,
  ct.TagCount,
  ct.AvgScore,
  ct.LastActive,
  cv.VoteTypeId,
  cv.VoteCategory,
  os.Status,
  os.DeletionVotes
ORDER BY rp.LastActivityDate DESC
LIMIT 100;