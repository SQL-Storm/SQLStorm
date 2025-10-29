-- {"query": "5024.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1320} 
WITH 
RecentUserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.AboutMe,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired,
    p.Id AS PostId
  FROM Tags t
  LEFT JOIN Posts p ON t.WikiPostId = p.Id
  WHERE t.IsModeratorOnly = 0
),
PostActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.ContentLicense,
    p.LastEditorUserId,
    p.LastEditDate,
    p.OwnerDisplayName,
    p.LastEditorDisplayName,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.Body
  FROM Posts p
),
JoinedData AS (
  SELECT
    pa.PostId,
    pa.PostTypeId,
    pa.Title,
    pa.Tags,
    pa.OwnerUserId,
    pa.CreationDate,
    pa.LastActivityDate,
    pa.ViewCount,
    pa.Score,
    pa.AnswerCount,
    pa.CommentCount,
    pa.FavoriteCount,
    pa.ParentId,
    pa.AcceptedAnswerId,
    pa.ContentLicense,
    pa.LastEditorUserId,
    pa.LastEditDate,
    pa.OwnerDisplayName,
    pa.LastEditorDisplayName,
    pa.ClosedDate,
    pa.CommunityOwnedDate,
    pa.Body,
    u.Reputation AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName2,
    COALESCE(vt2.Name, 'Unknown') AS LatestVoteType,
    v2.CreationDate AS LatestVoteDate,
    vt.Name AS TopVoteType
  FROM PostActivity pa
  LEFT JOIN Users u ON pa.OwnerUserId = u.Id
  LEFT JOIN Votes v2 ON pa.PostId = v2.PostId
  LEFT JOIN VoteTypes vt2 ON v2.VoteTypeId = vt2.Id
  LEFT JOIN VoteTypes vt ON vt2.Id = vt.Id
  WHERE pa.LastActivityDate > DATEADD(day, -180, GETDATE())
),
PerformanceBench AS (
  SELECT
    jd.PostId,
    jd.PostTypeId,
    jd.Title,
    jd.OwnerUserId,
    jd.CreationDate,
    jd.LastActivityDate,
    jd.ViewCount,
    jd.Score,
    jd.AnswerCount,
    jd.CommentCount,
    jd.FavoriteCount,
    jd.ParentId,
    jd.AcceptedAnswerId,
    jd.Body,
    JD.OwnerReputation,
    jd.LatestVoteType,
    jd.LatestVoteDate,
    jd.TopVoteType,
    ach.UserId IS NOT NULL AS HasAward
  FROM JoinedData jd
  LEFT JOIN (
    SELECT DISTINCT UserId
    FROM Badges
  ) ach ON ach.UserId = jd.OwnerUserId
),
Final AS (
  SELECT
    pb.PostId,
    pb.PostTypeId,
    pb.Title,
    pb.OwnerUserId,
    pb.CreationDate,
    pb.LastActivityDate,
    pb.ViewCount,
    pb.Score,
    pb.AnswerCount,
    pb.CommentCount,
    pb.FavoriteCount,
    pb.ParentId,
    pb.AcceptedAnswerId,
    pb.Body,
    pb.OwnerReputation,
    pb.LatestVoteType,
    pb.LatestVoteDate,
    pb.TopVoteType,
    pb.HasAward,
    -- Computed metrics with complex predicates
    CASE
      WHEN pb.ViewCount > 1000 THEN 1
      WHEN pb.ViewCount <= 0 THEN 0
      ELSE 0
    END AS IsPopular,
    CASE
      WHEN pb.Score > 0 THEN 'Positive'
      WHEN pb.Score < 0 THEN 'Negative'
      ELSE 'Neutral'
    END AS ScoreTrend,
    CASE
      WHEN pb.LastActivityDate > DATEADD(day, -7, GETDATE()) THEN 'Last7d'
      WHEN pb.LastActivityDate > DATEADD(day, -30, GETDATE()) THEN 'Last30d'
      ELSE 'Older'
    END AS ActivityBucket,
    CONCAT('https://stackoverflow.com/q/', pb.PostId) AS PostUrl,
    CASE
      WHEN pb.PostTypeId = 1 THEN 'Question'
      WHEN pb.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind
  FROM PerformanceBench pb
)
SELECT
  f.PostId,
  f.PostTypeId,
  f.Title,
  f.OwnerUserId,
  f.CreationDate,
  f.LastActivityDate,
  f.ViewCount,
  f.Score,
  f.AnswerCount,
  f.CommentCount,
  f.FavoriteCount,
  f.ParentId,
  f.AcceptedAnswerId,
  f.Body,
  f.OwnerReputation,
  f.LatestVoteType,
  f.LatestVoteDate,
  f.TopVoteType,
  f.HasAward,
  f.IsPopular,
  f.ScoreTrend,
  f.ActivityBucket,
  f.PostUrl,
  f.PostKind,
  (SELECT AVG(Reputation) FROM Users u2 WHERE u2.Id IN (SELECT OwnerUserId FROM Posts p2 WHERE p2.OwnerUserId IS NOT NULL)) AS AvgOwnerReputation,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = f.PostId) AS LinkCount,
  (SELECT STRING_AGG(t.TagName, ',') FROM Tags t JOIN Posts p ON p.Id = t.WikiPostId WHERE p.Id = f.PostId) AS LinkedTags
FROM Final f
ORDER BY f.LastActivityDate DESC
LIMIT 100;