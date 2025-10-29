-- {"query": "5868.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1046} 
WITH
S AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    u.Location,
    u.AboutMe,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    COALESCE(b.TotalBadges, 0) AS BadgeCount,
    COALESCE(v.ReceivedUpvotes, 0) AS ReceivedUpvotes
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId AS UserId, SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS ReceivedUpvotes
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY OwnerUserId
  ) v ON v.UserId = u.Id
),
P AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.ParentId,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '365 days'
),
L AS (
  SELECT
    pl.PostId,
    pt.Name AS LinkTypeName,
    pl.RelatedPostId
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  JOIN Posts pt ON pt.Id = pl.RelatedPostId
),
W AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN vt.Name IN ('UpMod','AcceptedByOriginator') THEN 1 ELSE 0 END) AS UpvotesSum
  FROM Votes v
  JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  GROUP BY v.PostId
),
C AS (
  SELECT
    c.PostId,
    AVG(CASE WHEN c.Text IS NOT NULL THEN LENGTH(c.Text) ELSE 0 END) AS AvgCommentLength
  FROM Comments c
  GROUP BY c.PostId
),
T AS (
  SELECT
    t.Id AS TagPostId,
    t.TagName,
    t.Count
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
R AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    CASE
      WHEN p.PostTypeId = 1 THEN 'Question'
      WHEN p.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS TypeLabel
  FROM Posts p
  WHERE p.LastActivityDate > p.CreationDate
)
SELECT
  S.UserId,
  S.DisplayName,
  S.Reputation,
  S.BadgeCount,
  S.ReceivedUpvotes,
  P.PostId,
  P.Title,
  P.CreationDate,
  P.Score,
  P.ViewCount,
  P.Body,
  P.Tags,
  P.OwnerUserId,
  P.AnswerCount,
  P.CommentCount,
  P.LastActivityDate,
  W.UpvotesSum,
  C.AvgCommentLength,
  CASE
    WHEN P.OwnerUserId IS NULL THEN 'Unknown'
    ELSE (SELECT DisplayName FROM Users WHERE Id = P.OwnerUserId)
  END AS OwnerDisplayName,
  STRING_AGG(DISTINCT L.LinkTypeName, ',') OVER (PARTITION BY P.PostId) AS LinkTypes,
  ARRAY_AGG(DISTINCT T.TagName) FILTER (WHERE T.TagPostId = P.PostId) AS RelatedTags,
  R.TypeLabel
FROM S
JOIN P ON P.OwnerUserId = S.UserId
LEFT JOIN L ON L.PostId = P.PostId
LEFT JOIN W ON W.PostId = P.PostId
LEFT JOIN C ON C.PostId = P.PostId
LEFT JOIN R ON R.PostId = P.PostId
LEFT JOIN Tags T ON T.TagPostId = P.PostId
GROUP BY
  S.UserId, S.DisplayName, S.Reputation, S.BadgeCount, S.ReceivedUpvotes,
  P.PostId, P.Title, P.CreationDate, P.Score, P.ViewCount, P.Body, P.Tags,
  P.OwnerUserId, P.AnswerCount, P.CommentCount, P.LastActivityDate,
  W.UpvotesSum, C.AvgCommentLength, OwnerDisplayName, R.TypeLabel
ORDER BY S.Reputation DESC, P.CreationDate DESC
LIMIT 100;