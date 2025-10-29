-- {"query": "5148.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 865} 
WITH recent_activity AS (
  SELECT
    p.Id AS PostId,
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
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.OwnerDisplayName,
    p.LastEditorDisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.Location,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
tag_metrics AS (
  SELECT
    rt.PostId,
    STRING_AGG(t.TagName, ',') AS TagList,
    ARRAY_LENGTH(string_to_array(TAGS, '><') , 1) AS TagCount
  FROM recent_activity rt
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(rt.Tags, 2, length(rt.Tags)-2), '><')) AS TagName
  ) t ON TRUE
  GROUP BY rt.PostId
),
correlated_history AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate AS HistoryDate,
    ph.UserId,
    ph.Comment,
    ph.Text AS HistoryText
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10,11,16,24,50)
),
top_influence AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.CreationDate,
    p.LastActivityDate,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC
    ) AS rn_by_owner
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
),
influential_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate,
    u.LastAccessDate,
    u.AccountId
  FROM Users u
  WHERE u.Reputation > 10000
),
final AS (
  SELECT
    r.PostId,
    r.PostTypeId,
    r.Title,
    r.CreationDate,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    r.CommentCount,
    r.AnswerCount,
    r.FavoriteCount,
    ud.UserName,
    ud.Reputation,
    tm.TagList,
    tm.TagCount,
    ch.HistoryDate,
    ch.PostHistoryTypeId,
    ch.Comment AS HistoryComment,
    ii.UserName AS Influencer,
    ci.PostId AS ChildPost
  FROM recent_activity r
  LEFT JOIN tag_metrics tm ON tm.PostId = r.Id
  LEFT JOIN correlated_history ch ON ch.PostId = r.Id
  LEFT JOIN influential_users ii ON ii.UserId = r.OwnerUserId
  LEFT JOIN (
    SELECT p.Id AS PostId, c.ParentId AS ChildPost
    FROM Posts p
    LEFT JOIN Posts c ON c.ParentId = p.Id
  ) ci ON ci.PostId = r.Id
  LEFT JOIN (SELECT 'dummy' AS d) d ON TRUE
)
SELECT
  PostId,
  PostTypeId,
  Title,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  CommentCount,
  AnswerCount,
  FavoriteCount,
  UserName AS OwnerDisplayName,
  Reputation,
  TagList,
  TagCount,
  HistoryDate,
  PostHistoryTypeId,
  HistoryComment,
  Influencer,
  ChildPost
FROM final
ORDER BY LastActivityDate DESC
LIMIT 200;