-- {"query": "337.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 20310} 
WITH
top_by_score AS (
  SELECT Id FROM Posts WHERE PostTypeId IN (1,2) ORDER BY Score DESC NULLS LAST LIMIT 150
),
top_by_views AS (
  SELECT Id FROM Posts WHERE PostTypeId = 1 ORDER BY ViewCount DESC NULLS LAST LIMIT 150
),
top_recent_activity AS (
  SELECT Id FROM Posts ORDER BY LastActivityDate DESC NULLS LAST LIMIT 150
),
candidates AS (
  SELECT Id FROM top_by_score
  UNION
  SELECT Id FROM top_by_views
  UNION
  SELECT Id FROM top_recent_activity
),
excluded AS (
  SELECT Id FROM Posts WHERE Score < 0 AND COALESCE(ViewCount,0) < 10
),
candidates_filtered AS (
  SELECT Id FROM candidates EXCEPT SELECT Id FROM excluded
),
posts_base AS (
  SELECT p.Id,
         p.PostTypeId,
         p.ParentId,
         p.AcceptedAnswerId,
         p.Title,
         p.Body,
         p.Tags,
         p.Score,
         p.ViewCount,
         p.AnswerCount,
         p.CreationDate,
         p.LastEditDate,
         p.LastActivityDate,
         p.ClosedDate,
         COALESCE(u.Id, -1) AS OwnerUserId,
         COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
         COALESCE(u.Reputation,0) AS OwnerReputation,
         (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id) AS RealAnswerCount,
         (SELECT AVG(a.Score) FROM Posts a WHERE a.ParentId = p.Id) AS AvgAnswerScore,
         (SELECT p2.Score FROM Posts p2 WHERE p2.Id = p.AcceptedAnswerId) AS AcceptedAnswerScore,
         (SELECT c.Text FROM Comments c WHERE c.PostId = p.Id ORDER BY c.CreationDate DESC LIMIT 1) AS LastCommentText
  FROM Posts p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  WHERE p.Id IN (SELECT Id FROM candidates_filtered)
),
vote_agg AS (
  SELECT PostId,
         SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
         SUM(CASE WHEN VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites,
         COUNT(*) AS TotalVotes
  FROM Votes
  WHERE PostId IN (SELECT Id FROM posts_base)
  GROUP BY PostId
),
comment_agg AS (
  SELECT PostId,
         COUNT(*) AS CommentCount2,
         AVG(COALESCE(Score,0)) AS AvgCommentScore,
         MAX(CreationDate) AS LastCommentDate,
         STRING_AGG(substring(regexp_replace(Text, E'\\s+',' ', 'g'),1,160), ' || ') AS RecentComments
  FROM Comments
  WHERE PostId IN (SELECT Id FROM posts_base)
  GROUP BY PostId
),
history_agg AS (
  SELECT PostId,
         SUM(CASE WHEN PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS EditCount,
         SUM(CASE WHEN PostHistoryTypeId IN (10,11) THEN 1 ELSE 0 END) AS CloseOpenCount,
         MAX(CreationDate) AS LastHistoryDate
  FROM PostHistory
  WHERE PostId IN (SELECT Id FROM posts_base)
  GROUP BY PostId
),
link_agg AS (
  SELECT PostId,
         SUM(CASE WHEN LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedCount,
         SUM(CASE WHEN LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateCount,
         MAX(CreationDate) AS LastLinkDate
  FROM PostLinks
  WHERE PostId IN (SELECT Id FROM posts_base)
  GROUP BY PostId
),
badges_by_owner AS (
  SELECT UserId,
         COUNT(*) AS BadgeCount,
         SUM(CASE WHEN TagBased = 1 THEN 1 ELSE 0 END) AS TagBadges,
         MAX(Date) AS LastBadgeDate,
         SUM(CASE WHEN Class = 1 THEN 5 WHEN Class = 2 THEN 3 ELSE 1 END) AS BadgeWeight
  FROM Badges
  WHERE UserId IN (SELECT OwnerUserId FROM posts_base)
  GROUP BY UserId
),
tag_index AS (
  SELECT p.Id AS PostId, NULLIF(trim(t.t), '') AS Tag
  FROM posts_base p
  LEFT JOIN LATERAL unnest(
    CASE WHEN p.Tags IS NULL THEN array[]::text[] ELSE string_to_array(substring(p.Tags, 2, char_length(p.Tags)-2), '><') END
  ) AS t(t) ON true
),
interesting_tags AS (
  SELECT TagName AS Tag FROM Tags WHERE Count > 300
  UNION
  SELECT DISTINCT Tag FROM tag_index WHERE Tag IS NOT NULL AND char_length(Tag) > 1
  EXCEPT
  SELECT 'deprecated'
),
similar_stats AS (
  SELECT p.Id AS PostId, COUNT(DISTINCT other.PostId) AS SimilarCount, AVG(o.Score) AS SimilarAvgScore
  FROM posts_base p
  JOIN tag_index ti ON ti.PostId = p.Id AND ti.Tag IS NOT NULL
  JOIN tag_index other ON other.Tag = ti.Tag AND other.PostId <> p.Id
  JOIN Posts o ON o.Id = other.PostId
  GROUP BY p.Id
)
SELECT
  p.Id AS post_id,
  COALESCE(p.Title, ('Answer to #' || p.ParentId::text)) AS title,
  COALESCE(trim(regexp_replace(COALESCE(p.Title,''), E'\\s+',' ', 'g')), '') AS title_normalized,
  GREATEST(0, COALESCE(p.Score,0))::int AS score,
  p.ViewCount AS views,
  COALESCE(v.UpVotes,0) AS vote_up,
  COALESCE(v.DownVotes,0) AS vote_down,
  COALESCE(v.TotalVotes,0) AS vote_total,
  COALESCE(c.CommentCount2,0) AS comments,
  COALESCE(b.BadgeCount,0) AS owner_badges,
  COALESCE(b.BadgeWeight,0) AS owner_badge_weight,
  COALESCE(p.RealAnswerCount,0) AS real_answer_count,
  COALESCE(p.AvgAnswerScore,0) AS avg_answer_score,
  COALESCE(p.AcceptedAnswerScore,0) AS accepted_answer_score,
  (COALESCE(p.AcceptedAnswerScore,0) - COALESCE(p.AvgAnswerScore,0)) AS accepted_vs_avg_gap,
  COALESCE(s.SimilarCount,0) AS similar_posts_count,
  COALESCE(s.SimilarAvgScore,0) AS similar_posts_avg_score,
  NULLIF(regexp_replace(COALESCE(p.Body,''), '<[^>]*>', '', 'g'), '') AS body_plain,
  substring(regexp_replace(COALESCE(p.Body,''), '<[^>]*>', '', 'g'),1,200) AS body_snippet,
  COALESCE(p.LastCommentText,'') AS last_comment_text,
  COALESCE(h.EditCount,0) AS edit_count,
  CASE WHEN p.ClosedDate IS NOT NULL OR COALESCE(h.CloseOpenCount,0) > 0 THEN true ELSE false END AS is_closed,
  EXTRACT(epoch FROM (now() - p.CreationDate))/86400.0 AS age_days,
  cardinality(regexp_split_to_array(COALESCE(p.Title,''), E'\\s+')) AS title_word_count,
  CASE WHEN COALESCE(v.DownVotes,0) = 0 THEN COALESCE(v.UpVotes,0)::numeric ELSE COALESCE(v.UpVotes,0)::numeric / COALESCE(v.DownVotes,1)::numeric END AS up_down_ratio,
  CASE WHEN COALESCE(v.TotalVotes,0) = 0 THEN 0 ELSE COALESCE(v.UpVotes,0)::numeric / COALESCE(v.TotalVotes,0)::numeric END AS pct_upvotes,
  (COALESCE(v.UpVotes,0) + COALESCE(c.CommentCount2,0)*2 + COALESCE(p.AnswerCount,0)*5 + ln(GREATEST(COALESCE(p.ViewCount,1),1)))::numeric AS engagement_score,
  (COALESCE(p.Score,0)
   + COALESCE(v.UpVotes,0)*0.4
   - COALESCE(v.DownVotes,0)*0.9
   + ln(GREATEST(COALESCE(p.ViewCount,1),1))*1.5
   + sqrt(GREATEST(COALESCE(p.AnswerCount,0),0)+1)*2
   + COALESCE(b.BadgeWeight,0)*0.2
   + COALESCE(p.AcceptedAnswerScore - COALESCE(p.AvgAnswerScore,0),0)*1.1
   - COALESCE(l.DuplicateCount,0)*2
  ) AS score_adjusted,
  RANK() OVER (ORDER BY
   (COALESCE(p.Score,0)
   + COALESCE(v.UpVotes,0)*0.4
   - COALESCE(v.DownVotes,0)*0.9
   + ln(GREATEST(COALESCE(p.ViewCount,1),1))*1.5
   + sqrt(GREATEST(COALESCE(p.AnswerCount,0),0)+1)*2
   + COALESCE(b.BadgeWeight,0)*0.2
   + COALESCE(p.AcceptedAnswerScore - COALESCE(p.AvgAnswerScore,0),0)*1.1
   - COALESCE(l.DuplicateCount,0)*2)
  ) AS global_rank,
  RANK() OVER (PARTITION BY COALESCE(ti.Tag,'__no_tag__') ORDER BY
   (COALESCE(p.Score,0)
   + COALESCE(v.UpVotes,0)*0.4
   - COALESCE(v.DownVotes,0)*0.9
   + ln(GREATEST(COALESCE(p.ViewCount,1),1))*1.5
   + sqrt(GREATEST(COALESCE(p.AnswerCount,0),0)+1)*2
   + COALESCE(b.BadgeWeight,0)*0.2
   + COALESCE(p.AcceptedAnswerScore - COALESCE(p.AvgAnswerScore,0),0)*1.1
   - COALESCE(l.DuplicateCount,0)*2)
  ) AS tag_rank,
  SUM(p.ViewCount) OVER (PARTITION BY COALESCE(ti.Tag,'__no_tag__') ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_tag_views,
  (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND COALESCE(a.Score,0) > COALESCE(p.AvgAnswerScore,0)) AS answers_higher_than_avg,
  (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND (p.AcceptedAnswerId IS NOT NULL AND COALESCE(a.Score,0) > COALESCE(p.AcceptedAnswerScore, -999999) )) AS answers_higher_than_accepted,
  ti.Tag AS primary_tag,
  CASE WHEN ti.Tag IS NOT NULL THEN ti.Tag ELSE '__no_tag__' END AS tag_sanitized
FROM posts_base p
LEFT JOIN vote_agg v ON v.PostId = p.Id
LEFT JOIN comment_agg c ON c.PostId = p.Id
LEFT JOIN history_agg h ON h.PostId = p.Id
LEFT JOIN link_agg l ON l.PostId = p.Id
LEFT JOIN badges_by_owner b ON b.UserId = p.OwnerUserId
LEFT JOIN similar_stats s ON s.PostId = p.Id
LEFT JOIN tag_index ti ON ti.PostId = p.Id
WHERE
    (
      ti.Tag IN (SELECT Tag FROM interesting_tags)
      OR
      (COALESCE(p.Score,0) + COALESCE(v.UpVotes,0)*0.4 + ln(GREATEST(COALESCE(p.ViewCount,1),1))*1.2) > 50
    )
ORDER BY score_adjusted DESC NULLS LAST
LIMIT 200;