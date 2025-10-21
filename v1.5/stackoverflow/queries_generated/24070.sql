-- {"query": "24070.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 4257} 
WITH recent_posts AS (
    SELECT *
    FROM Posts
    WHERE CreationDate >= NOW() - INTERVAL '30 days'
      AND PostTypeId = 1
),
tag_list AS (
    SELECT p.Id AS PostId,
           unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    FROM recent_posts p
),
tag_counts AS (
    SELECT t.PostId,
           COUNT(DISTINCT t.TagName) AS TagCount
    FROM tag_list t
    GROUP BY t.PostId
),
top_close_votes AS (
    SELECT ph.PostId,
           ph.CreationDate,
           ph.UserId,
           ph.Text AS CloseReason,
           ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
),
vote_totals AS (
    SELECT v.PostId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
           SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCount
    FROM Votes v
    GROUP BY v.PostId
),
comment_counts AS (
    SELECT c.PostId,
           COUNT(*) AS CommentCount
    FROM Comments c
    GROUP BY c.PostId
),
merged AS (
    SELECT p.Id,
           p.Title,
           p.Score,
           p.AnswerCount,
           p.ViewCount,
           p.OwnerUserId,
           COALESCE(tc.TagCount,0) AS TagCount,
           COALESCE(tc2.CloseReason,'N/A') AS CloseReason,
           COALESCE(vt.UpVotes,0) AS UpVotes,
           COALESCE(vt.DownVotes,0) AS DownVotes,
           COALESCE(vt.FavoriteCount,0) AS FavoriteCount,
           COALESCE(cc.CommentCount,0) AS CommentCount,
           ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RankByScore,
           ROW_NUMBER() OVER (ORDER BY (vt.UpVotes - vt.DownVotes) DESC) AS RankByNet
    FROM recent_posts p
    LEFT JOIN tag_counts tc ON p.Id = tc.PostId
    LEFT JOIN top_close_votes tc2 ON p.Id = tc2.PostId AND tc2.rn = 1
    LEFT JOIN vote_totals vt ON p.Id = vt.PostId
    LEFT JOIN comment_counts cc ON p.Id = cc.PostId
),
filter_union AS (
    SELECT *
    FROM merged
    WHERE Score >= 10
    UNION ALL
    SELECT *
    FROM merged
    WHERE Score < 10
      AND UpVotes > 20
),
duplicates AS (
    SELECT pl.PostId, pl.RelatedPostId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
)
SELECT fu.Id,
       fu.Title,
       fu.Score,
       fu.AnswerCount,
       fu.ViewCount,
       fu.OwnerUserId,
       fu.TagCount,
       fu.CloseReason,
       fu.UpVotes,
       fu.DownVotes,
       fu.FavoriteCount,
       fu.CommentCount,
       fu.RankByScore,
       fu.RankByNet,
       CASE WHEN d.RelatedPostId IS NOT NULL THEN 'Duplicate' ELSE 'Unique' END AS Status,
       CASE WHEN fu.Title IS NULL THEN 0 ELSE length(fu.Title) END AS TitleLength,
       (SELECT COUNT(*) FROM Comments c2 WHERE c2.PostId = fu.Id) AS CorrelatedCommentCount
FROM filter_union fu
LEFT JOIN duplicates d ON fu.Id = d.PostId
WHERE fu.Title LIKE '%SQL%'
   OR fu.Title LIKE '%database%'
  AND fu.ViewCount > 1000
  AND NOT EXISTS (
        SELECT 1
        FROM Badges b
        WHERE b.UserId = fu.OwnerUserId
          AND b.Name = 'Legend'
    )
  AND (fu.CommentCount IS NULL OR fu.CommentCount > 0)
ORDER BY fu.RankByScore, fu.RankByNet
LIMIT 50;