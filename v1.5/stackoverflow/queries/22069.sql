-- {"query": "22069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 923} 
WITH top_users AS (
  SELECT Id, Reputation, DisplayName, COALESCE(Location, 'Unknown') AS Location
  FROM Users
  WHERE Reputation > 1000 AND LastAccessDate > '2020-01-01'
),
question_stats AS (
  SELECT OwnerUserId, 
         COUNT(*) AS num_questions, 
         AVG(COALESCE(Score, 0)) AS avg_score,
         SUM(LENGTH(COALESCE(Title, ''))) AS total_title_length
  FROM Posts
  WHERE PostTypeId = 1 AND OwnerUserId IS NOT NULL
  GROUP BY OwnerUserId
  HAVING COUNT(*) > 0
),
answer_stats AS (
  SELECT OwnerUserId, 
         COUNT(*) AS num_answers, 
         SUM(COALESCE(Score, 0)) AS total_score_answers,
         AVG(EXTRACT(EPOCH FROM COALESCE(LastActivityDate, CreationDate) - CreationDate)) AS avg_activity_time
  FROM Posts
  WHERE PostTypeId = 2 AND OwnerUserId IS NOT NULL
  GROUP BY OwnerUserId
),
badge_counts AS (
  SELECT UserId, 
         COUNT(*) AS num_badges, 
         SUM(CASE WHEN Class = 1 THEN 10 WHEN Class = 2 THEN 5 ELSE 1 END) AS badge_points,
         STRING_AGG(Name, ', ' ORDER BY Date DESC) AS badge_list
  FROM Badges
  GROUP BY UserId
),
post_history_agg AS (
  SELECT PostId, COUNT(*) AS edit_count
  FROM PostHistory
  WHERE PostHistoryTypeId IN (4,5,6)
  GROUP BY PostId
)
SELECT tu.Id, 
       UPPER(SUBSTRING(tu.DisplayName, 1, 5)) || '...' AS ShortName,
       tu.Reputation,
       tu.Location,
       COALESCE(qs.num_questions, 0) AS questions,
       ROUND(COALESCE(qs.avg_score, 0), 2) AS avg_q_score,
       COALESCE(qs.total_title_length, 0) AS title_chars,
       COALESCE(ans.num_answers, 0) AS answers,
       COALESCE(ans.total_score_answers, 0) AS answer_total,
       ROUND(COALESCE(ans.avg_activity_time, 0), 2) AS avg_act_time_seconds,
       bc.num_badges,
       bc.badge_points,
       bc.badge_list,
       RANK() OVER (ORDER BY tu.Reputation DESC, COALESCE(qs.num_questions, 0) ASC) AS rep_rank,
       LAG(tu.Reputation) OVER (ORDER BY tu.Reputation DESC) - tu.Reputation AS rep_diff,
       ROW_NUMBER() OVER (PARTITION BY LEFT(tu.Location, 10) ORDER BY tu.Reputation DESC) AS loc_rank,
       CASE WHEN bc.badge_points > 50 THEN 'Elite' WHEN bc.badge_points > 20 THEN 'Veteran' ELSE 'Novice' END AS badge_level,
       CONCAT(tu.Id, '-', COALESCE(qs.num_questions, 0)) AS user_code,
       (SELECT MAX(COALESCE(Score, 0)) FROM Posts WHERE OwnerUserId = tu.Id AND PostTypeId = 1) AS max_q_score_correlated,
       (SELECT COUNT(DISTINCT PostId) FROM Comments WHERE UserId = tu.Id) AS distinct_comment_posts,
       pha.edit_count AS total_edits_on_posts
FROM top_users tu
LEFT OUTER JOIN question_stats qs ON tu.Id = qs.OwnerUserId
LEFT OUTER JOIN answer_stats ans ON tu.Id = ans.OwnerUserId
LEFT OUTER JOIN badge_counts bc ON tu.Id = bc.UserId
FULL OUTER JOIN post_history_agg pha ON pha.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = tu.Id)
WHERE tu.Reputation BETWEEN 1000 AND 50000
  AND (COALESCE(qs.num_questions, 0) > 5 OR COALESCE(ans.num_answers, 0) > 10)
  AND (bc.badge_points IS NULL OR bc.badge_points > 10)
  AND NOT (qs.avg_score IS NULL AND ans.num_answers IS NULL)
UNION ALL
SELECT Id, DisplayName, Reputation, Location, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM Users
WHERE Id = 1
ORDER BY rep_rank DESC, Id ASC;