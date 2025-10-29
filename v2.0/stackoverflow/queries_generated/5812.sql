-- {"query": "5812.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 887} 
WITH
RecentActivePosts AS (
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
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.AcceptedAnswerId,
    COALESCE(p.ParentId, 0) AS ParentId
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
TagStats AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionsWithTag,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
    MAX(p.ViewCount) AS MaxViews
  FROM Posts p
  JOIN UNNEST(string_to_array(TRIM(BOTH '><' FROM p.Tags), '><')) AS t(TagName)
  GROUP BY t.TagName
),
TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC) AS rn
  FROM Users u
  WHERE u.AccountId IS NOT NULL
),
UserBadgeActivity AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgesEarned,
    MAX(b.Date) AS LastBadgeDate,
    STRING_AGG(b.Name, ',') AS BadgeNames
  FROM Badges b
  GROUP BY b.UserId
),
PostHistorySummary AS (
  SELECT
    ph.PostId,
    MAX(CASE WHEN pht.Name IS NOT NULL THEN pht.Name END) AS HistoryTypeName,
    MAX(ph.CreationDate) AS LatestHistoryDate
  FROM PostHistory ph
  LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
  GROUP BY ph.PostId
),
CrossLinkMetrics AS (
  SELECT
    pl.PostId,
    COUNT(*) AS LinkCount,
    SUM(CASE WHEN lt.Name ILIKE 'duplicate%' THEN 1 ELSE 0 END) AS DuplicateLinks
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  GROUP BY pl.PostId
)
SELECT
  rp.PostId,
  rp.PostTypeId,
  rp.OwnerUserId,
  ru.DisplayName AS OwnerDisplayName,
  rp.Title,
  rp.Tags,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.Score,
  rp.ViewCount,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount,
  CASE
    WHEN rp.AcceptedAnswerId IS NOT NULL THEN 1
    ELSE 0
  END AS HasAcceptedAnswer,
  CASE
    WHEN rp.ParentId IS NOT NULL THEN rp.ParentId
    ELSE NULL
  END AS ParentPostId,
  ht.LatestHistoryDate,
  ht.HistoryTypeName,
  cm.MaxViews AS MaxRelatedPostViews,
  ts.TagName,
  ts.TagCount,
  ts.QuestionsWithTag,
  ts.AvgQuestionScore,
  bu.BadgesEarned,
  bu.LastBadgeDate,
  bu.BadgeNames,
  upn.rn AS TopUserRank,
  clm.LinkCount,
  clm.DuplicateLinks
FROM RecentActivePosts rp
LEFT JOIN Users ru ON rp.OwnerUserId = ru.Id
LEFT JOIN PostHistorySummary ht ON rp.Id = ht.PostId
LEFT JOIN TopUsers upn ON rp.OwnerUserId = upn.UserId
LEFT JOIN UserBadgeActivity bu ON rp.OwnerUserId = bu.UserId
LEFT JOIN TagStats ts ON REGEXP_SPLIT_TO_TABLE(rp.Tags, '>') IS NOT NULL AND TRUE
LEFT JOIN CrossLinkMetrics clm ON rp.Id = clm.PostId
WHERE rp.ViewCount > 0
  AND rp.Score >= (SELECT AVG(Score) FROM Posts)
ORDER BY rp.LastActivityDate DESC
LIMIT 100;