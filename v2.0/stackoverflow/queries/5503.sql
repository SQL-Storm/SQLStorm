-- {"query": "5503.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 719}
WITH
RecentActive AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
    MAX(p.LastActivityDate) AS LastActivity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName) AS rn
  FROM Tags t
  WHERE COALESCE(t.IsModeratorOnly, FALSE) = FALSE
),
TagEngagement AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Tags,
    p.Score,
    pc.CommentCount,
    pv.VoteTypeId,
    pv.UserId AS VoterId,
    pv.CreationDate AS VoteDate
  FROM Posts p
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ) pc ON pc.PostId = p.Id
  LEFT JOIN Votes pv ON pv.PostId = p.Id
  WHERE p.PostTypeId IN (1,2)
),
ComplicatedFilter AS (
  SELECT
    te.PostId,
    te.Title,
    te.OwnerUserId,
    te.Tags,
    te.Score,
    te.CommentCount,
    te.VoteDate,
    u.DisplayName AS OwnerName,
    u.Reputation,
    u.LastAccessDate
  FROM TagEngagement te
  LEFT JOIN Users u ON u.Id = te.OwnerUserId
  WHERE te.Score > 0
    AND (te.CommentCount > 5 OR te.VoteDate IS NOT NULL)
),
Windowed AS (
  SELECT
    cf.PostId,
    cf.Title,
    cf.OwnerUserId,
    cf.Tags,
    cf.Score,
    cf.CommentCount,
    cf.VoteDate,
    cf.OwnerName,
    cf.Reputation,
    cf.LastAccessDate,
    ROW_NUMBER() OVER (PARTITION BY cf.OwnerUserId ORDER BY cf.Score DESC, cf.VoteDate DESC NULLS LAST) AS rn_by_owner
  FROM ComplicatedFilter cf
),
Agg AS (
  SELECT
    w.OwnerUserId,
    w.OwnerName,
    SUM(w.Score) AS TotalScoreByOwner,
    COUNT(*) AS PostCountByOwner,
    MAX(w.LastAccessDate) AS LastSeen
  FROM Windowed w
  GROUP BY w.OwnerUserId, w.OwnerName
),
HotUsers AS (
  SELECT
    a.OwnerUserId,
    a.OwnerName,
    a.TotalScoreByOwner,
    a.PostCountByOwner,
    a.LastSeen,
    RANK() OVER (ORDER BY a.TotalScoreByOwner DESC, a.LastSeen DESC) AS r
  FROM Agg a
)
SELECT
  hu.OwnerUserId,
  hu.OwnerName,
  hu.TotalScoreByOwner,
  hu.PostCountByOwner,
  hu.LastSeen,
  urc.QuestionCount,
  urc.AnswerCount,
  urc.Reputation
FROM HotUsers hu
LEFT JOIN RecentActive urc ON urc.UserId = hu.OwnerUserId
WHERE hu.r <= 50
ORDER BY hu.TotalScoreByOwner DESC, hu.LastSeen DESC;