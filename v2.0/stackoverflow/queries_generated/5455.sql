-- {"query": "5455.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 784} 
WITH highly_active_users AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
),
recent_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.Body,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate
  FROM Posts p
  WHERE p.CreationDate > CURRENT_DATE - INTERVAL '30 days'
),
top_tags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.Count > 100
),
comp_posts AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerUserId,
    rp.ViewCount,
    rp.Score,
    rp.LastActivityDate,
    CASE
      WHEN rp.PostTypeId = 1 THEN 'Question'
      WHEN rp.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind,
    pv.Name AS LastEditorName
  FROM recent_posts rp
  LEFT JOIN Users pv ON rp.LastEditorUserId = pv.Id
),
activity_summary AS (
  SELECT
    c.PostId,
    c.Text,
    c.CreationDate,
    c.UserId,
    c.UserDisplayName,
    c.Score AS CommentScore,
    pv.Reputation AS UserReputation
  FROM Comments c
  LEFT JOIN Users pv ON c.UserId = pv.Id
  WHERE c.CreationDate > CURRENT_DATE - INTERVAL '14 days'
),
cte_join AS (
  SELECT
    cu.Id AS UserId,
    cu.DisplayName,
    cu.Reputation,
    cu.Views,
    cu.UpVotes,
    cu.DownVotes,
    cu.Location,
    cu.AccountId,
    pu.PostId,
    pu.Title,
    pu.ViewCount,
    pu.Score,
    pu.LastActivityDate,
    pu.PostKind,
    a.LastEditorName,
    asb.CommentScore,
    asb.UserReputation
  FROM highly_active_users cu
  LEFT JOIN comp_posts pu ON pu.OwnerUserId = cu.Id
  LEFT JOIN (
    SELECT rp.PostId, pv.Name AS LastEditorName
    FROM comp_posts rp
    LEFT JOIN Users pv ON rp.LastEditorUserId = pv.Id
  ) a ON a.PostId = pu.PostId
  LEFT JOIN activity_summary asb ON asb.PostId = pu.PostId
  WHERE cu.rn <= 100
)
SELECT
  cu.UserId,
  cu.DisplayName,
  cu.Reputation,
  cu.Views,
  cu.UpVotes,
  cu.DownVotes,
  cu.Location,
  cu.AccountId,
  pu.PostId,
  pu.Title,
  pu.ViewCount,
  pu.Score,
  pu.LastActivityDate,
  pu.PostKind,
  cu.LastEditorName,
  asb.CommentScore,
  asb.UserReputation
FROM cte_join cu
LEFT JOIN comp_posts pu ON pu.OwnerUserId = cu.UserId
LEFT JOIN activity_summary asb ON asb.PostId = pu.PostId
ORDER BY cu.Reputation DESC, pu.LastActivityDate DESC
LIMIT 500;