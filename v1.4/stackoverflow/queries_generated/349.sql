-- {"query": "349.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 11453} 
WITH PostEngagement AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.Tags,
    COALESCE(u.DisplayName, p.OwnerDisplayName, 'Unknown') AS OwnerName,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.FavoriteCount,
    p.LastEditorDisplayName,
    p.LastEditDate,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    (CASE WHEN p.PostTypeId = 1 THEN 2 ELSE 0 END
     + (p.Score * 3)
     + (p.ViewCount / 50)
     + (p.CommentCount * 4)
    ) AS Engagement,
    CASE WHEN p.ClosedDate IS NULL THEN 1 ELSE 0 END AS OpenFlag,
    (SELECT COUNT(*) FROM Posts px WHERE px.OwnerUserId = p.OwnerUserId AND px.CreationDate > NOW() - INTERVAL '30 days') AS RecentPostsOwner
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
TopQ AS (
  SELECT pe.*,
         ROW_NUMBER() OVER (ORDER BY pe.Engagement DESC, pe.LastActivityDate DESC) AS Rank,
         CASE WHEN LENGTH(pe.Title) > 100 THEN LEFT(pe.Title, 97) || '...' ELSE pe.Title END AS TitleSnippet
  FROM PostEngagement pe
  WHERE pe.PostTypeId = 1 AND pe.OpenFlag = 1
),
TopA AS (
  SELECT pe.*,
         ROW_NUMBER() OVER (ORDER BY pe.Engagement DESC, pe.LastActivityDate DESC) AS Rank,
         CASE WHEN LENGTH(pe.Title) > 100 THEN LEFT(pe.Title, 97) || '...' ELSE pe.Title END AS TitleSnippet
  FROM PostEngagement pe
  WHERE pe.PostTypeId = 2 AND pe.OpenFlag = 1
)
SELECT
  Id,
  CASE PostTypeId WHEN 1 THEN 'Question' WHEN 2 THEN 'Answer' END AS PostType,
  Title,
  Engagement,
  OwnerName,
  CreationDate,
  LastActivityDate,
  ViewCount,
  Tags,
  Rank,
  TitleSnippet
FROM TopQ
UNION ALL
SELECT
  Id,
  CASE PostTypeId WHEN 1 THEN 'Question' WHEN 2 THEN 'Answer' END AS PostType,
  Title,
  Engagement,
  OwnerName,
  CreationDate,
  LastActivityDate,
  ViewCount,
  Tags,
  Rank,
  TitleSnippet
FROM TopA
ORDER BY Engagement DESC, Rank ASC
LIMIT 500;