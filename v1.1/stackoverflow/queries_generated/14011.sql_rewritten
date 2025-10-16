-- {"query": "14011.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 28020, "output_tokens": 12655} 
WITH cte AS (
  SELECT 
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.OwnerUserId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.Title,
    p.Tags,
    u.Reputation AS OwnerReputation,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate,
    u.Location AS OwnerLocation,
    u.AboutMe AS OwnerAboutMe,
    u.Views AS OwnerViews,
    u.UpVotes AS OwnerUpVotes,
    u.DownVotes AS OwnerDownVotes,
    b.Name AS BadgeName,
    b.Date AS BadgeDate,
    b.Class AS BadgeClass,
    b.TagBased AS BadgeTagBased
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
),
post_quality_score AS (
  SELECT 
    PostId, 
    SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN VoteTypeId = 4 THEN 1 ELSE 0 END) AS OffensiveVotes,
    SUM(CASE WHEN VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotes,
    SUM(CASE WHEN VoteTypeId = 7 THEN 1 ELSE 0 END) AS ReopenVotes,
    SUM(CASE WHEN VoteTypeId = 10 THEN 1 ELSE 0 END) AS DeletionVotes,
    SUM(CASE WHEN VoteTypeId = 11 THEN 1 ELSE 0 END) AS UndeletionVotes
  FROM Votes
  GROUP BY PostId
),
post_quality_metrics AS (
  SELECT
    c.PostId,
    c.PostTypeId,
    c.CreationDate,
    c.OwnerUserId,
    c.ParentId,
    c.AcceptedAnswerId,
    c.Score,
    c.ViewCount,
    c.AnswerCount,
    c.CommentCount,
    c.FavoriteCount,
    c.ClosedDate,
    c.CommunityOwnedDate,
    c.Title,
    c.Tags,
    c.OwnerReputation,
    c.OwnerCreationDate,
    c.OwnerLastAccessDate,
    c.OwnerLocation,
    c.OwnerAboutMe,
    c.OwnerViews,
    c.OwnerUpVotes,
    c.OwnerDownVotes,
    c.BadgeName,
    c.BadgeDate,
    c.BadgeClass,
    c.BadgeTagBased,
    pqs.UpVotes,
    pqs.DownVotes,
    pqs.OffensiveVotes,
    pqs.CloseVotes,
    pqs.ReopenVotes,
    pqs.DeletionVotes,
    pqs.UndeletionVotes
  FROM cte c
  LEFT JOIN post_quality_score pqs ON c.PostId = pqs.PostId
)
SELECT 
  PostId,
  PostTypeId,
  CreationDate,
  OwnerUserId,
  ParentId,
  AcceptedAnswerId,
  CASE 
    WHEN PostTypeId = 1 THEN 
      (Score + UpVotes * 10 - DownVotes * 5 + OffensiveVotes * -20 + CloseVotes * -15 + ReopenVotes * 5 + DeletionVotes * -20 + UndeletionVotes * 10) / (ViewCount + 1)
    WHEN PostTypeId = 2 THEN
      (Score + UpVotes * 10 - DownVotes * 5 + OffensiveVotes * -20 + CloseVotes * -15 + ReopenVotes * 5 + DeletionVotes * -20 + UndeletionVotes * 10) / (ViewCount + 1)
  END AS PostQualityScore,
  ViewCount,
  AnswerCount,
  CommentCount,
  FavoriteCount,
  ClosedDate,
  CommunityOwnedDate,
  Title,
  Tags,
  OwnerReputation,
  OwnerCreationDate,
  OwnerLastAccessDate,
  OwnerLocation,
  OwnerAboutMe,
  OwnerViews,
  OwnerUpVotes,
  OwnerDownVotes,
  BadgeName,
  BadgeDate,
  BadgeClass,
  BadgeTagBased,
  UpVotes,
  DownVotes,
  OffensiveVotes,
  CloseVotes,
  ReopenVotes,
  DeletionVotes,
  UndeletionVotes
FROM post_quality_metrics
ORDER BY PostQualityScore DESC
LIMIT 100;