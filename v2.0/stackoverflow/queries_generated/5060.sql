-- {"query": "5060.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 950} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.PostTypeId,
    p.ParentId
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= now() - interval '90 days'
),
recent_activity AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.OwnerUserId,
    q.LastActivityDate,
    q.CommentCount,
    q.FavoriteCount,
    q.Body,
    q.Tags,
    COALESCE(a.AnswerCount, 0) AS AnswerCount
  FROM recent_questions q
  LEFT JOIN (
    SELECT ParentId, count(*) AS AnswerCount
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
  ) a ON a.ParentId = q.PostId
),
tag_profiles AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    u.ProfileImageUrl,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    b.Name AS BadgeName,
    b.Date AS BadgeDate,
    b.Class AS BadgeClass,
    b.TagBased
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
),
complex_metrics AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.ViewCount,
    ra.Score,
    ra.OwnerUserId,
    ra.CommentCount,
    ra.FavoriteCount,
    ra.Body,
    ra.Tags,
    ra.AnswerCount,
    v_total_up(vv) AS total_votes
  FROM recent_activity ra
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
                   SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
  ) vv ON vv.PostId = ra.PostId
),
final_select AS (
  SELECT
    cr.PostId,
    cr.Title,
    cr.Tags,
    cr.CreationDate,
    cr.LastActivityDate,
    cr.ViewCount,
    cr.Score,
    cr.OwnerUserId,
    cr.CommentCount,
    cr.FavoriteCount,
    cr.Body,
    cr.AnswerCount,
    tv.UpVotes,
    tv.DownVotes,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.Location,
    u.ProfileImageUrl,
    CASE
      WHEN cr.OwnerUserId IS NULL THEN 'Anonymous'
      ELSE u.DisplayName
    END AS EffectiveOwner,
    json_agg(DISTINCT jsonb_build_object(
      'TagName', t.TagName,
      'Count', t.Count
    )) FILTER (WHERE t.TagName IS NOT NULL) AS TagInfo
  FROM recent_activity cr
  LEFT JOIN Votes tv ON tv.PostId = cr.PostId
  LEFT JOIN Users u ON u.Id = cr.OwnerUserId
  LEFT JOIN Tags t ON t.Id = (
    SELECT Id FROM Tags
    WHERE t.TagName = ANY(string_to_array(cr.Tags, '><'))
    LIMIT 1
  )
  GROUP BY
    cr.PostId, cr.Title, cr.Tags, cr.CreationDate, cr.LastActivityDate,
    cr.ViewCount, cr.Score, cr.OwnerUserId, cr.CommentCount, cr.FavoriteCount,
    cr.Body, cr.AnswerCount, tv.UpVotes, tv.DownVotes, u.DisplayName, u.Reputation,
    u.Location, u.ProfileImageUrl
)
SELECT
  PostId,
  Title,
  Tags,
  CreationDate,
  LastActivityDate,
  ViewCount,
  Score,
  OwnerUserId,
  CommentCount,
  FavoriteCount,
  Body,
  AnswerCount,
  UpVotes,
  DownVotes,
  EffectiveOwner,
  Reputation,
  Location,
  ProfileImageUrl,
  TagInfo
FROM final_select
ORDER BY LastActivityDate DESC
LIMIT 500;