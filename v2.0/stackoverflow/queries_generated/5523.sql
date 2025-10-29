-- {"query": "5523.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1052} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    p.ContentLicense,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
TagPopularity AS (
  SELECT
    t.TagName,
    t.Count AS RawCount,
    (t.Count * 1.0 / NULLIF((SELECT SUM(Count) FROM Tags), 0)) AS Popularity
  FROM Tags t
  WHERE t.TagName IS NOT NULL
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    u.AccountId,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostsOwned,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpvotesCast,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS DownvotesCast
  FROM Users u
),
Combined AS (
  SELECT
    rh.PostId,
    rh.Title,
    rh.Tags,
    rh.CreationDate AS PostCreationDate,
    rh.Score,
    rh.ViewCount,
    rh.OwnerUserId,
    rh.LastActivityDate,
    rh.CommentCount,
    rh.AnswerCount,
    rh.FavoriteCount,
    rh.Body,
    rh.ContentLicense,
    tp.TagName,
    tp.Popularity,
    ua.UserId AS AuthorUserId,
    ua.DisplayName AS AuthorName,
    ua.Reputation AS AuthorReputation
  FROM RecentHot rh
  LEFT JOIN TagPopularity tp
    ON ',' + rh.Tags + ',' LIKE '%,' + tp.TagName + ',%'
  LEFT JOIN UserActivity ua
    ON rh.OwnerUserId = ua.UserId
),
WindowAgg AS (
  SELECT
    c.*,
    SUM(c.Score) OVER (PARTITION BY c.TagName ORDER BY c.LastActivityDate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS Rolling30DayScore,
  FROM (
    SELECT
      PostId,
      Title,
      Tags,
      PostCreationDate,
      Score,
      ViewCount,
      OwnerUserId,
      LastActivityDate,
      CommentCount,
      AnswerCount,
      FavoriteCount,
      Body,
      ContentLicense,
      TagName,
      Popularity,
      AuthorUserId,
      AuthorName,
      AuthorReputation
    FROM Combined
  ) AS c
),
OuterJoinExample AS (
  SELECT
    w.PostId,
    w.Title,
    w.Tags,
    w.PostCreationDate,
    w.Score,
    w.ViewCount,
    w.OwnerUserId,
    w.LastActivityDate,
    w.CommentCount,
    w.AnswerCount,
    w.FavoriteCount,
    w.Body,
    w.ContentLicense,
    w.TagName,
    w.Popularity,
    w.AuthorUserId,
    w.AuthorName,
    w.AuthorReputation,
    w.Rolling30DayScore,
    -- Subquery: latest comment by a non-owner on the post
    (SELECT MAX(Cre.creationDate)
     FROM Comments Cre
     WHERE Cre.PostId = w.PostId
       AND Cre.UserId IS NOT NULL) AS LatestCommentDate,
    -- Correlated subquery with NULL handling
    (SELECT COUNT(*) FROM Votes V
     WHERE V.PostId = w.PostId
       AND V.VoteTypeId IN (2, 6) -- upvote or close vote
       AND V.CreationDate > w.PostCreationDate - INTERVAL '7' DAY) AS RecentVotes7d
  FROM WindowAgg w
)
SELECT
  o.PostId,
  o.Title,
  o.Tags,
  o.PostCreationDate,
  o.Score,
  o.ViewCount,
  o.OwnerUserId,
  o.LastActivityDate,
  o.CommentCount,
  o.AnswerCount,
  o.FavoriteCount,
  o.Body,
  o.ContentLicense,
  o.TagName,
  o.Popularity,
  o.AuthorUserId,
  o.AuthorName,
  o.AuthorReputation,
  o.Rolling30DayScore,
  o.LatestCommentDate,
  o.RecentVotes7d
FROM OuterJoinExample o
WHERE o.Popularity > 0.01
  AND o.Rolling30DayScore IS NOT NULL
ORDER BY o.Rolling30DayScore DESC, o.LastActivityDate DESC
LIMIT 200;