WITH all_posts AS (
  SELECT p.Id,
         p.Tags,
         p.Score,
         p.ViewCount,
         p.AnswerCount,
         p.CreationDate,
         p.OwnerUserId,
         CASE WHEN p.Score >= 10 AND p.AnswerCount > 0 THEN TRUE ELSE FALSE END AS HighQuality,
         (p.ClosedDate IS NOT NULL) AS IsClosed
  FROM Posts p
  WHERE p.PostTypeId = 1
),
tag_arrayed AS (
  SELECT ap.Id,
         ap.OwnerUserId,
         unnest(string_to_array(substring(ap.Tags FROM 2 FOR length(ap.Tags) - 2), '><')) AS TagName,
         ap.Score,
         ap.ViewCount,
         ap.AnswerCount,
         ap.CreationDate,
         ap.IsClosed
  FROM all_posts ap
),
votes_agg AS (
  SELECT va.PostId,
         SUM(CASE WHEN va.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN va.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
         SUM(CASE WHEN va.VoteTypeId = 1 THEN 1 ELSE 0 END) AS Accepted
  FROM Votes va
  GROUP BY va.PostId
),
joined AS (
  SELECT ta.Id,
         ta.OwnerUserId,
         ta.TagName,
         ta.Score,
         ta.ViewCount,
         ta.AnswerCount,
         ta.CreationDate,
         ta.IsClosed,
         v.UpVotes,
         v.DownVotes,
         v.Accepted
  FROM tag_arrayed ta
  LEFT JOIN votes_agg v ON v.PostId = ta.Id
),
top_closed AS (
  SELECT * FROM joined WHERE IsClosed = TRUE
),
top_open AS (
  SELECT * FROM joined
  WHERE IsClosed = FALSE AND Score >= 10
),
combined AS (
  SELECT * FROM top_closed
  UNION ALL
  SELECT * FROM top_open
),
ranked AS (
  SELECT Id,
         OwnerUserId,
         TagName,
         Score,
         ViewCount,
         AnswerCount,
         CreationDate,
         IsClosed,
         UpVotes,
         DownVotes,
         Accepted,
         ROW_NUMBER() OVER (PARTITION BY TagName ORDER BY Score DESC, ViewCount DESC) AS rn
  FROM combined
),
top5 AS (
  SELECT * FROM ranked WHERE rn <= 5
)
SELECT
  t5.TagName,
  u.DisplayName,
  t5.Id AS PostId,
  t5.Score,
  t5.ViewCount,
  t5.AnswerCount,
  t5.UpVotes,
  t5.DownVotes,
  t5.Accepted,
  CASE WHEN t5.Score >= 10 AND t5.AnswerCount > 0 THEN TRUE ELSE FALSE END AS HighQuality,
  t5.IsClosed,
  (SELECT AVG(u2.reputation)
     FROM Users u2
     WHERE u2.Id = t5.OwnerUserId
       AND u2.CreationDate <= t5.CreationDate) AS AvgReputationAtCreation,
  (SELECT string_agg(ta.TagName, ' ')
     FROM tag_arrayed ta
     WHERE ta.Id = t5.Id
     GROUP BY ta.Id) AS AllTags,
  t5.rn
FROM top5 t5
JOIN Users u ON u.Id = t5.OwnerUserId
ORDER BY t5.TagName, t5.rn;