WITH PostBase AS (
  SELECT p.Id,
         p.Title,
         p.PostTypeId,
         p.Score,
         p.ViewCount,
         p.CreationDate,
         p.OwnerUserId,
         p.Tags,
         COALESCE(p.LastActivityDate, (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id)) AS LastActivityDate,
         u.DisplayName AS OwnerDisplayName,
         u.Reputation AS OwnerReputation
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
),
FullPostInfo AS (
  SELECT b.Id,
         b.Title,
         b.PostTypeId,
         b.Score,
         b.ViewCount,
         b.CreationDate,
         b.LastActivityDate,
         b.OwnerDisplayName,
         b.OwnerReputation,
         COALESCE((SELECT SUM(v2.BountyAmount) FROM Votes v2 WHERE v2.PostId = b.Id AND v2.VoteTypeId = 8), 0) AS BountyTotal,
         COALESCE((SELECT COUNT(*) FROM Votes v3 WHERE v3.PostId = b.Id AND v3.VoteTypeId = 2), 0) AS UpVotes,
         COALESCE((SELECT COUNT(*) FROM Votes v4 WHERE v4.PostId = b.Id AND v4.VoteTypeId = 3), 0) AS DownVotes,
         (
           SELECT STRING_AGG(t, ',')
           FROM (
                 SELECT t
                 FROM (
                       SELECT TRIM(value) AS t
                       FROM UNNEST(
                             COALESCE(string_to_array(substring(b.Tags FROM 2 FOR CHAR_LENGTH(b.Tags) - 2), '><'), ARRAY[]::TEXT[])
                           ) AS s(value)
                       ORDER BY value
                      ) AS inner_t
               LIMIT 3
               ) AS s
         ) AS Top3Tags
  FROM PostBase b
),
DailyTop AS (
  SELECT dt.*,
         ROW_NUMBER() OVER (PARTITION BY DATE_TRUNC('day', dt.CreationDate) ORDER BY dt.Score DESC, dt.ViewCount DESC) AS rn
  FROM FullPostInfo dt
),
WeeklyTop AS (
  SELECT wt.*,
         ROW_NUMBER() OVER (PARTITION BY DATE_TRUNC('week', wt.CreationDate) ORDER BY wt.Score DESC, wt.ViewCount DESC) AS rn
  FROM FullPostInfo wt
)
SELECT Id, Title, OwnerDisplayName, OwnerReputation, PostTypeId, Score, ViewCount, CreationDate, LastActivityDate, UpVotes, DownVotes, BountyTotal, Top3Tags
FROM DailyTop
WHERE rn = 1
UNION ALL
SELECT Id, Title, OwnerDisplayName, OwnerReputation, PostTypeId, Score, ViewCount, CreationDate, LastActivityDate, UpVotes, DownVotes, BountyTotal, Top3Tags
FROM WeeklyTop
WHERE rn = 1
ORDER BY Score DESC
LIMIT 100;