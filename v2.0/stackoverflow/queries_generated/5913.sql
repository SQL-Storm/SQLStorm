-- {"query": "5913.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 796} 
WITH recent_q AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.CreationDate,
         p.ViewCount,
         p.Score,
         p.OwnerUserId,
         p.Tags,
         p.LastActivityDate,
         p.Body,
         p.PostTypeId,
         p.AnswerCount,
         p.CommentCount,
         p.FavoriteCount,
         p.AcceptedAnswerId
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
tag_stats AS (
  SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tag,
         COUNT(*) AS questions_last_30d
  FROM recent_q r
  GROUP BY 1
),
top_tags AS (
  SELECT tag
  FROM tag_stats
  ORDER BY questions_last_30d DESC
  LIMIT 10
),
expanded AS (
  SELECT r.*,
         (SELECT STRING_AGG(vt.Name, ',')
          FROM Votes v
          JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
          WHERE v.PostId = r.PostId
            AND v.CreationDate >= r.CreationDate
            AND v.VoteTypeId IN (2,3,10,11,12,14,15,16)) AS subsequent_votes
  FROM recent_q r
),
complex AS (
  SELECT e.PostId,
         e.Title,
         e.CreationDate,
         e.ViewCount,
         e.Score,
         e.OwnerUserId,
         e.Tags,
         e.LastActivityDate,
         e.Body,
         e.AcceptedAnswerId,
         e.AnswerCount,
         e.CommentCount,
         e.FavoriteCount,
         e.subsequent_votes,
         ROW_NUMBER() OVER (
           PARTITION BY e.OwnerUserId
           ORDER BY e.Score DESC, e.ViewCount DESC
         ) AS rn_by_owner
  FROM expanded e
  LEFT JOIN top_tags tt ON 1=1
  WHERE (e.Tags LIKE '%' || (SELECT tag FROM top_tags LIMIT 1) || '%')
     OR (e.Title ILIKE '%benchmark%' OR e.Body ILIKE '%benchmark%')
),
windowed AS (
  SELECT c.*,
         SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) OVER (PARTITION BY OwnerUserId
                                                        ORDER BY CreationDate
                                                        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS positive_score_window
  FROM complex c
),
distinct_user AS (
  SELECT w.PostId,
         w.Title,
         w.CreationDate,
         w.ViewCount,
         w.Score,
         w.OwnerUserId,
         u.DisplayName AS OwnerDisplayName,
         u.Reputation,
         w.Tags,
         w.LastActivityDate,
         w.Body,
         w.AcceptedAnswerId,
         w.AnswerCount,
         w.CommentCount,
         w.FavoriteCount,
         w.subsequent_votes,
         w.rn_by_owner,
         w.positive_score_window
  FROM windowed w
  LEFT JOIN Users u ON u.Id = w.OwnerUserId
)
SELECT DISTINCT
       du.PostId,
       du.Title,
       du.CreationDate,
       du.ViewCount,
       du.Score,
       du.OwnerUserId,
       du.OwnerDisplayName,
       du.Reputation,
       du.Tags,
       du.LastActivityDate,
       du.Body,
       du.AcceptedAnswerId,
       du.AnswerCount,
       du.CommentCount,
       du.FavoriteCount,
       du.subsequent_votes,
       du.rn_by_owner,
       du.positive_score_window
FROM distinct_user du
ORDER BY du.positive_score_window DESC
LIMIT 50;