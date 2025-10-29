-- {"query": "5428.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 944} 
WITH TopActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
Filters AS (
  SELECT
    t1.Id AS PostId,
    t1.Title,
    t1.Tags,
    t1.ViewCount,
    t1.Score,
    t1.AnswerCount,
    t1.CommentCount,
    t1.OwnerUserId,
    t1.CreationDate,
    t1.LastActivityDate,
    t1.PostTypeId,
    t2.Name AS PostTypeName,
    COALESCE(vc.TotalVotes, 0) AS TotalVotes,
    COALESCE(bb.BadgeCount, 0) AS UserBadges
  FROM TopActivePosts t1
  LEFT JOIN PostTypes t2 ON t1.PostTypeId = t2.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS TotalVotes
    FROM Votes
    WHERE VoteTypeId IN (2, 3) -- UpMod and DownMod
    GROUP BY PostId
  ) vc ON vc.PostId = t1.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS BadgeCount
    FROM Badges
    GROUP BY UserId
  ) bb ON bb.UserId = t1.OwnerUserId
  WHERE t1.rn <= 50
),
CorrelatedComments AS (
  SELECT
    f.PostId,
    f.Title,
    f.ViewCount,
    f.Score,
    f.AnswerCount,
    f.CommentCount,
    f.OwnerUserId,
    f.CreationDate,
    f.LastActivityDate,
    f.PostTypeId,
    f.PostTypeName,
    f.TotalVotes,
    f.UserBadges,
    c.Id AS CommentId,
    c.UserDisplayName,
    c.Text,
    c.CreationDate AS CommentDate,
    c.Score AS CommentScore
  FROM Filters f
  LEFT JOIN Comments c ON c.PostId = f.PostId
  WHERE c.CreationDate < f.LastActivityDate OR c.CreationDate IS NULL
),
Windowed AS (
  SELECT
    PostId,
    Title,
    PostTypeName,
    OwnerUserId,
    CreationDate,
    LastActivityDate,
    ViewCount,
    Score,
    AnswerCount,
    CommentCount,
    TotalVotes,
    UserBadges,
    CommentId,
    UserDisplayName,
    Text,
    CommentDate,
    CommentScore,
    ROW_NUMBER() OVER (
      PARTITION BY PostId
      ORDER BY CommentDate DESC NULLS LAST, CommentScore DESC NULLS LAST
    ) AS cn
  FROM CorrelatedComments
),
Aggregated AS (
  SELECT
    PostId,
    Title,
    PostTypeName,
    OwnerUserId,
    CreationDate,
    LastActivityDate,
    ViewCount,
    Score,
    AnswerCount,
    CommentCount,
    TotalVotes,
    UserBadges,
    MAX(CASE WHEN cn = 1 THEN UserDisplayName END) AS LastCommentBy,
    MAX(CASE WHEN cn = 1 THEN Text END) AS LastCommentText,
    MAX(CASE WHEN cn = 1 THEN CommentDate END) AS LastCommentDate
  FROM Windowed
  GROUP BY
    PostId,
    Title,
    PostTypeName,
    OwnerUserId,
    CreationDate,
    LastActivityDate,
    ViewCount,
    Score,
    AnswerCount,
    CommentCount,
    TotalVotes,
    UserBadges
)
SELECT
  a.PostId,
  a.Title,
  a.PostTypeName,
  a.OwnerUserId,
  a.CreationDate,
  a.LastActivityDate,
  a.ViewCount,
  a.Score,
  a.AnswerCount,
  a.CommentCount,
  a.TotalVotes,
  a.UserBadges,
  a.LastCommentBy,
  a.LastCommentText,
  a.LastCommentDate
FROM Aggregated a
ORDER BY a.LastActivityDate DESC NULLS LAST, a.TotalVotes DESC, a.ViewCount DESC
LIMIT 200;