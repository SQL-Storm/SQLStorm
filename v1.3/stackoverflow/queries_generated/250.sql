-- {"query": "250.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 5186} 
WITH
activity_union AS (
  SELECT OwnerUserId AS UserId, CreationDate AS ts, 'post' AS kind, Id::text AS ref FROM Posts WHERE OwnerUserId IS NOT NULL
  UNION ALL
  SELECT UserId, CreationDate, 'comment', Id::text FROM Comments WHERE UserId IS NOT NULL
  UNION ALL
  SELECT UserId, CreationDate, 'vote', Id::text FROM Votes WHERE UserId IS NOT NULL
  UNION ALL
  SELECT UserId, CreationDate, 'history', Id::text FROM PostHistory WHERE UserId IS NOT NULL
),
last_activity AS (
  SELECT au.UserId,
         MAX(au.ts)                          AS LastActivityDate,
         COUNT(*) FILTER (WHERE au.kind='post')    AS PostsActivityCount,
         COUNT(*) FILTER (WHERE au.kind='comment') AS CommentsActivityCount,
         COUNT(*) FILTER (WHERE au.kind='vote')    AS VotesActivityCount,
         COUNT(*) FILTER (WHERE au.kind='history') AS HistoryActivityCount
  FROM activity_union au
  GROUP BY au.UserId
),
user_posts AS (
  SELECT OwnerUserId::int AS UserId,
         SUM(CASE WHEN PostTypeId=1 THEN 1 ELSE 0 END) AS Questions,
         SUM(CASE WHEN PostTypeId=2 THEN 1 ELSE 0 END) AS Answers,
         SUM(COALESCE(Score,0)) AS TotalScore,
         AVG(CASE WHEN Score IS NOT NULL THEN Score::numeric END) AS AvgScore,
         AVG(EXTRACT(EPOCH FROM (COALESCE(LastActivityDate,CreationDate) - CreationDate))) FILTER (WHERE LastActivityDate IS NOT NULL) AS AvgTimeToActivitySeconds
  FROM Posts
  WHERE OwnerUserId IS NOT NULL
  GROUP BY OwnerUserId
),
accepted_counts AS (
  SELECT p.OwnerUserId::int AS UserId,
         COUNT(*) FILTER (WHERE p.AcceptedAnswerId IS NOT NULL AND EXISTS(SELECT 1 FROM Posts a WHERE a.Id = p.AcceptedAnswerId)) AS AcceptedAnswersCount
  FROM Posts p
  WHERE p.PostTypeId = 1
  GROUP BY p.OwnerUserId
),
badge_counts AS (
  SELECT UserId::int,
         COUNT(*) AS BadgeCount,
         COUNT(*) FILTER (WHERE Class=1) AS Gold,
         COUNT(*) FILTER (WHERE Class=2) AS Silver,
         COUNT(*) FILTER (WHERE Class=3) AS Bronze,
         COUNT(*) FILTER (WHERE TagBased=1) AS TagBadges
  FROM Badges
  GROUP BY UserId
),
tag_exploded AS (
  SELECT p.OwnerUserId::int AS UserId,
         lower(trim(tg.tag)) AS tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) AS tag
  ) tg
  WHERE p.PostTypeId = 1
    AND p.OwnerUserId IS NOT NULL
    AND p.Tags IS NOT NULL
    AND char_length(p.Tags) > 2
),
user_tag_stats AS (
  SELECT UserId,
         COUNT(*) AS TagUses,
         COUNT(DISTINCT tag) AS DistinctTags
  FROM tag_exploded
  GROUP BY UserId
),
user_tag_top AS (
  SELECT UserId, tag AS TopTag
  FROM (
    SELECT UserId, tag,
           ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY COUNT(*) OVER (PARTITION BY UserId, tag) DESC, tag) AS rn
    FROM tag_exploded
  ) t
  WHERE rn = 1
),
deleted_history AS (
  SELECT UserId::int, COUNT(*) AS DeletedCount
  FROM PostHistory
  WHERE PostHistoryTypeId = 12 AND UserId IS NOT NULL
  GROUP BY UserId
),
edits_window AS (
  SELECT ph.UserId::int,
         ph.PostId,
         ph.Id AS HistoryId,
         ph.CreationDate,
         ROW_NUMBER() OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate DESC) AS rn,
         COUNT(*) OVER (PARTITION BY ph.UserId) AS TotalEdits
  FROM PostHistory ph
  WHERE ph.UserId IS NOT NULL
),
top_users AS (
  SELECT u.Id::int AS UserId,
         u.Reputation,
         u.DisplayName,
         RANK() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS rep_rank,
         RANK() OVER (ORDER BY COALESCE(l.LastActivityDate, u.LastAccessDate) DESC NULLS LAST) AS activity_rank,
         COALESCE(bc.BadgeCount,0) AS BadgeCount
  FROM Users u
  LEFT JOIN last_activity l ON l.UserId = u.Id
  LEFT JOIN badge_counts bc ON bc.UserId = u.Id
),
champions AS (
  SELECT UserId FROM top_users WHERE rep_rank <= 50
  UNION
  SELECT UserId FROM top_users WHERE activity_rank <= 50
  UNION
  SELECT UserId FROM top_users WHERE BadgeCount >= 5
),
final AS (
  SELECT u.Id::int AS UserId,
         u.DisplayName,
         u.Reputation,
         COALESCE(l.LastActivityDate, u.LastAccessDate) AS LastSeen,
         COALESCE(up.Questions,0) AS Questions,
         COALESCE(up.Answers,0) AS Answers,
         COALESCE(ac.AcceptedAnswersCount,0) AS AcceptedAnswers,
         COALESCE(up.TotalScore,0) AS TotalScore,
         ROUND(COALESCE(up.AvgScore,0)::numeric,2) AS AvgScore,
         COALESCE(bc.BadgeCount,0) AS Badges,
         COALESCE(bc.Gold,0) AS Gold,
         COALESCE(bc.Silver,0) AS Silver,
         COALESCE(bc.Bronze,0) AS Bronze,
         COALESCE(bc.TagBadges,0) AS TagBadges,
         COALESCE(uts.TagUses,0) AS TagUses,
         COALESCE(uts.DistinctTags,0) AS DistinctTags,
         utt.TopTag,
         COALESCE(dh.DeletedCount,0) AS DeletedRevisions,
         COALESCE(ew.TotalEdits,0) AS TotalEdits,
         ew.CreationDate AS MostRecentEditDate,
         -- correlated subquery: median score of this user's posts
         (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY Score) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.Score IS NOT NULL) AS MedianScore,
         -- derived ratios with NULL logic and protections
         CASE
           WHEN COALESCE(up.Answers,0) = 0 THEN NULL
           ELSE ROUND( (COALESCE(ac.AcceptedAnswersCount,0)::numeric / NULLIF(COALESCE(up.Answers,0),0))::numeric, 4)
         END AS AcceptedPerAnswerRatio,
         -- Influence score: crafted expression mixing many signals and null-safe operations
         (
           COALESCE(u.Reputation,0) * 0.45
           + COALESCE(up.Answers,0) * 2.2
           + COALESCE(ac.AcceptedAnswersCount,0) * 6.5
           + COALESCE(bc.Gold,0) * 11
           + COALESCE(bc.Silver,0) * 3.5
           + COALESCE(bc.Bronze,0) * 1.2
           - COALESCE(dh.DeletedCount,0) * 2.5
           + COALESCE(uts.DistinctTags,0) * 0.35
           + (CASE WHEN u.WebsiteUrl IS NOT NULL AND trim(u.WebsiteUrl) <> '' THEN 2 ELSE 0 END)
           + (CASE WHEN u.Location IS NOT NULL THEN 0.5 ELSE 0 END)
         )::numeric(18,4) AS InfluenceScore,
         -- compact textual summary with string ops and NULL logic
         TRIM(CONCAT_WS(' | ',
               COALESCE(NULLIF(u.DisplayName,''),'(anonymous)'),
               COALESCE(utt.TopTag, '(no-top-tag)'),
               CONCAT('Q:',COALESCE(up.Questions,0),' A:',COALESCE(up.Answers,0)),
               COALESCE(NULLIF(u.Location,''), '(unknown)')
         )) AS Brief
  FROM Users u
  LEFT JOIN last_activity l ON l.UserId = u.Id
  LEFT JOIN user_posts up ON up.UserId = u.Id
  LEFT JOIN accepted_counts ac ON ac.UserId = u.Id
  LEFT JOIN badge_counts bc ON bc.UserId = u.Id
  LEFT JOIN user_tag_stats uts ON uts.UserId = u.Id
  LEFT JOIN user_tag_top utt ON utt.UserId = u.Id
  LEFT JOIN deleted_history dh ON dh.UserId = u.Id
  LEFT JOIN edits_window ew ON ew.UserId = u.Id AND ew.rn = 1
  WHERE u.Id IN (SELECT UserId FROM champions)
)
SELECT *
FROM final
ORDER BY InfluenceScore DESC NULLS LAST, LastSeen DESC NULLS LAST, Reputation DESC NULLS LAST
LIMIT 200;