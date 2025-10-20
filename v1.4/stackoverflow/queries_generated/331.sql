-- {"query": "331.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 31813} 
WITH Q1 AS (
  SELECT
    p.Id AS PostId,
    p.Title AS Title,
    p.Tags AS Tags,
    p.PostTypeId AS PostTypeId,
    p.CreationDate AS CreationDate,
    COALESCE(p.LastActivityDate, p.CreationDate) AS LastActivityDate,
    p.Score AS Score,
    p.ViewCount AS ViewCount,
    p.OwnerUserId AS OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(v.DownVotes, 0) AS DownVotes,
    COALESCE(cmt.CommentCount, 0) AS CommentCount,
    COALESCE(ug.GoldBadges, 0) AS GoldBadges,
    EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate)) AS ActivitySpan,
    (p.Score + COALESCE(v.UpVotes, 0) * 2.0 + COALESCE(ug.GoldBadges, 0) * 4.0
       - COALESCE(cmt.CommentCount, 0) * 0.5 - COALESCE(v.DownVotes, 0) * 0.75
       + COALESCE(p.ViewCount, 0) * 0.05
       + CASE 
           WHEN COALESCE(EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate)), 0) > 0
           THEN 200000.0 / COALESCE(EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate)), 1)
           ELSE 0
         END
    ) AS EngagementScore,
    CASE WHEN p.Tags IS NOT NULL
         THEN array_to_string(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'), ',')
         ELSE NULL
    END AS TagNamesList
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
  ) v ON v.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ) cmt ON cmt.PostId = p.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS GoldBadges
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
  ) ug ON ug.UserId = p.OwnerUserId
  WHERE p.PostTypeId = 1
  AND p.CreationDate >= NOW() - INTERVAL '365 days'
),
Q2 AS (
  SELECT
    p.Id AS PostId,
    p.Title AS Title,
    p.Tags AS Tags,
    p.PostTypeId AS PostTypeId,
    p.CreationDate AS CreationDate,
    COALESCE(p.LastActivityDate, p.CreationDate) AS LastActivityDate,
    p.Score AS Score,
    p.ViewCount AS ViewCount,
    p.OwnerUserId AS OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(v.DownVotes, 0) AS DownVotes,
    COALESCE(cmt.CommentCount, 0) AS CommentCount,
    COALESCE(ug.GoldBadges, 0) AS GoldBadges,
    EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate)) AS ActivitySpan,
    (p.Score + COALESCE(v.UpVotes, 0) * 2.0 + COALESCE(ug.GoldBadges, 0) * 4.0
       - COALESCE(cmt.CommentCount, 0) * 0.5 - COALESCE(v.DownVotes, 0) * 0.75
       + COALESCE(p.ViewCount, 0) * 0.05
       + CASE 
           WHEN COALESCE(EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate)), 0) > 0
           THEN 200000.0 / COALESCE(EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate)), 1)
           ELSE 0
         END
    ) AS EngagementScore,
    CASE WHEN p.Tags IS NOT NULL
         THEN array_to_string(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'), ',')
         ELSE NULL
    END AS TagNamesList
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
  ) v ON v.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ) cmt ON cmt.PostId = p.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS GoldBadges
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
  ) ug ON ug.UserId = p.OwnerUserId
  WHERE p.PostTypeId IN (4,5)
)
SELECT
  PostId,
  Title,
  Tags,
  PostTypeId,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  OwnerUserId,
  OwnerDisplayName,
  UpVotes,
  DownVotes,
  CommentCount,
  GoldBadges,
  ActivitySpan,
  EngagementScore,
  TagNamesList,
  ROW_NUMBER() OVER (PARTITION BY PostTypeId ORDER BY EngagementScore DESC) AS RankWithinType
FROM (
  SELECT * FROM Q1
  UNION ALL
  SELECT * FROM Q2
) AS AllPosts
ORDER BY PostTypeId, RankWithinType
LIMIT 500;