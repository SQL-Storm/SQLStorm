-- {"query": "54.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1086} 
WITH recent_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    COALESCE(u.AboutMe, '') AS AboutMe,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
    MAX(p.LastActivityDate) AS LastActivePostDate,
    STRING_AGG(DISTINCT bl.Name, ',') FILTER (WHERE bl.Name IS NOT NULL) AS BadgesOwned,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Badges bl ON bl.UserId = u.Id
  WHERE u.AccountId IS NOT NULL
  GROUP BY u.Id
),
tag_usage AS (
  SELECT
    u.Id AS UserId,
    t.TagName,
    COUNT(*) AS TagUsageCount
  FROM Users u
  JOIN Posts p ON p.OwnerUserId = u.Id
  JOIN UNNEST(string_to_array(p.Tags, '><')) AS t(TagName) ON TRUE
  GROUP BY u.Id, t.TagName
),
complex_post_stats AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.OwnerDisplayName,
    p.LastEditorDisplayName,
    p.LastEditDate,
    p.ContentLicense,
    CASE
      WHEN p.Score > 0 THEN 'positive'
      WHEN p.Score = 0 THEN 'zero'
      ELSE 'negative'
    END AS ScoreCategory,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.LastActivityDate DESC, p.ViewCount DESC
    ) AS ActivityRank
  FROM Posts p
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN Tags t ON t.Id = (CASE
      WHEN POSITION('<' IN p.Tags) > 0 THEN CAST(NULL AS int)
      ELSE t.Id
    END)
  WHERE p.PostTypeId IN (1,2)
    AND p.LastActivityDate IS NOT NULL
),
top_relevant AS (
  SELECT
    cps.Id,
    cps.Title,
    cps.PostTypeId,
    cps.Tags,
    cps.CreationDate,
    cps.LastActivityDate,
    cps.Score,
    cps.ViewCount,
    cps.OwnerUserId,
    cps.AcceptedAnswerId,
    cps.CommentCount,
    cps.FavoriteCount,
    cps.ParentId,
    cps.OwnerDisplayName,
    cps.LastEditorDisplayName,
    cps.LastEditDate,
    cps.ContentLicense,
    cps.ScoreCategory,
    cps.ActivityRank,
    ROW_NUMBER() OVER (
      ORDER BY cps.Score DESC, cps.ViewCount DESC, cps.LastActivityDate DESC
    ) AS GlobalRank
  FROM complex_post_stats cps
  WHERE cps.ActivityRank <= 10
)
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserDisplayName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate,
  u.Location,
  u.AboutMe,
  ru.PostCount,
  ru.UpVotesReceived,
  ru.DownVotesReceived,
  ru.LastActivePostDate,
  ru.BadgesOwned,
  ru.GoldBadges,
  ru.SilverBadges,
  ru.BronzeBadges,
  tr.TagName,
  tr.TagUsageCount,
  tp.Id AS PostId,
  tp.Title AS PostTitle,
  tp.PostTypeId,
  tp.Tags AS PostTags,
  tp.CreationDate AS PostCreationDate,
  tp.LastActivityDate AS PostLastActivityDate,
  tp.Score AS PostScore,
  tp.ViewCount AS PostViewCount,
  tp.CommentCount,
  tp.FavoriteCount,
  tp.ParentId
FROM Users u
LEFT JOIN recent_user_activity ru ON ru.UserId = u.Id
LEFT JOIN tag_usage tr ON tr.UserId = u.Id
LEFT JOIN top_relevant tp ON tp.OwnerUserId = u.Id
WHERE u.Reputation > 1000
  OR COALESCE(u.Location, '') ILIKE '%USA%'
ORDER BY ru.LastActivePostDate DESC NULLS LAST, tp.GlobalRank NULLS LAST
LIMIT 100;