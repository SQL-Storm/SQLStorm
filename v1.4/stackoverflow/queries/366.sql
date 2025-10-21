-- {"query": "366.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 28765} 
WITH
PostSet AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.OwnerUserId,
         p.Tags,
         p.ViewCount,
         p.Score,
         p.CommentCount,
         p.CreationDate
  FROM Posts p
  WHERE p.PostTypeId = 1
),
Owners AS (
  SELECT
     ps.PostId,
     ps.Title,
     ps.OwnerUserId,
     COALESCE(u.DisplayName, 'Community') AS Owner,
     COALESCE(u.Reputation, 0) AS Reputation,
     ps.ViewCount,
     ps.Score,
     ps.CommentCount,
     ps.Tags,
     ps.CreationDate
  FROM PostSet ps
  LEFT JOIN Users u ON ps.OwnerUserId = u.Id
),
TagCounts AS (
  SELECT o.PostId,
         o.Title,
         o.Owner,
         o.OwnerUserId,
         o.Reputation,
         o.ViewCount,
         o.Score,
         o.CommentCount,
         o.Tags,
         o.CreationDate,
         CASE
           WHEN o.Tags IS NULL OR length(o.Tags) <= 2 THEN 0
           ELSE array_length(string_to_array(substr(o.Tags, 2, length(o.Tags) - 2), '><'), 1)
         END AS TagCount
  FROM Owners o
),
VotesAgg AS (
  SELECT tc.PostId,
         SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotesTotal,
         SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotesTotal
  FROM TagCounts tc
  LEFT JOIN Votes vt ON tc.PostId = vt.PostId
  GROUP BY tc.PostId
),
LastHist AS (
  SELECT ph.PostId, MAX(ph.CreationDate) AS LastHistoryDate
  FROM PostHistory ph
  GROUP BY ph.PostId
),
Eng AS (
  SELECT
     tc.PostId,
     tc.Title,
     tc.Owner,
     tc.Reputation,
     tc.ViewCount,
     tc.Score,
     tc.CommentCount,
     tc.TagCount,
     COALESCE(va.UpVotesTotal, 0) AS UpVotesTotal,
     COALESCE(va.DownVotesTotal, 0) AS DownVotesTotal,
     COALESCE(lh.LastHistoryDate, tc.CreationDate) AS LastHistoryDate,
     (tc.Score * 2.0 + tc.ViewCount * 0.5 + tc.CommentCount * 1.2 +
      COALESCE(va.UpVotesTotal, 0) * 0.5 - COALESCE(va.DownVotesTotal, 0) * 0.5) AS EngagementScore,
     (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = tc.PostId) AS LinkCount,
     EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = tc.OwnerUserId AND b.Class = 1) AS HasGoldBadge,
     ROW_NUMBER() OVER (PARTITION BY tc.Owner ORDER BY (tc.Score * 2.0 + tc.ViewCount * 0.5 + tc.CommentCount * 1.2 +
      COALESCE(va.UpVotesTotal, 0) * 0.5 - COALESCE(va.DownVotesTotal, 0) * 0.5) DESC) AS OwnerRank
  FROM TagCounts tc
  LEFT JOIN VotesAgg va ON tc.PostId = va.PostId
  LEFT JOIN LastHist lh ON tc.PostId = lh.PostId
)
SELECT PostId, Title, Owner, EngagementScore
FROM Eng
WHERE EngagementScore > 100
UNION ALL
SELECT PostId, Title, Owner, EngagementScore
FROM Eng
WHERE HasGoldBadge
ORDER BY EngagementScore DESC
LIMIT 200;