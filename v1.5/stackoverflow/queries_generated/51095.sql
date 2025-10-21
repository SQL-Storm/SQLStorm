-- {"query": "51095.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 934} 

WITH question_owners AS (
    SELECT p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount
    FROM Posts p
    INNER JOIN PostTypes pt ON p.PostTypeId = pt.Id AND pt.Name = 'Question'
    WHERE p.DeletedDate IS NULL AND p.OwnerUserId > 0
),
active_users AS (
    SELECT u.Id, u.Reputation, u.UpVotes, u.DownVotes,
           COUNT(DISTINCT ph.PostId) as edit_count,
           COUNT(DISTINCT c.PostId) as comment_count
    FROM Users u
    INNER JOIN PostHistory ph ON ph.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    WHERE u.Reputation >= 1000 AND u.CreationDate >= NOW() - INTERVAL '5 years'
    GROUP BY u.Id, u.Reputation, u.UpVotes, u.DownVotes
    HAVING COUNT(DISTINCT ph.PostId) + COUNT(DISTINCT c.PostId) >= 10
),
tag_stats AS (
    SELECT t.TagName, t.Count as tag_usage,
           AVG(p.Score) as avg_question_score,
           AVG(p.ViewCount) as avg_views
    FROM Tags t
    INNER JOIN Posts p ON string_to_array(
        substring(p.Tags from 2 for length(p.Tags)-2), 
        '><'
    ) @> ARRAY[t.TagName]::text[]
    INNER JOIN question_owners qo ON p.Id = qo.Id
    WHERE p.Score > 0
    GROUP BY t.TagName, t.Count
    HAVING t.Count > 50
),
bounty_analysis AS (
    SELECT v.PostId, SUM(v.BountyAmount) as total_bounty,
           AVG(v.BountyAmount) as avg_bounty,
           COUNT(*) as bounty_count
    FROM Votes v
    INNER JOIN VoteTypes vt ON v.VoteTypeId = vt.Id 
    WHERE vt.Name IN ('BountyStart', 'BountyClose')
    GROUP BY v.PostId
),
high_impact_collaborations AS (
    SELECT qo1.OwnerUserId as poster_id,
           au.Id as editor_id,
           COUNT(DISTINCT ph.Id) as collaboration_events,
           SUM(qo1.Score) as total_score_impact,
           AVG(qo1.ViewCount) as avg_visibility
    FROM question_owners qo1
    INNER JOIN active_users au ON au.Id != qo1.OwnerUserId
    INNER JOIN PostHistory ph ON ph.PostId = qo1.Id AND ph.UserId = au.Id
    LEFT JOIN bounty_analysis ba ON ba.PostId = qo1.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)  -- Edits
      AND qo1.CreationDate >= au.CreationDate
      AND (ba.total_bounty > 0 OR qo1.Score >= 5)
    GROUP BY qo1.OwnerUserId, au.Id
    HAVING COUNT(DISTINCT ph.Id) >= 3
)
SELECT 
    au.DisplayName as collaborator_name,
    au.Reputation as collaborator_reputation,
    au.UpVotes - au.DownVotes as net_votes,
    hic.collaboration_events,
    hic.total_score_impact,
    hic.avg_visibility,
    ts.TagName as primary_tag,
    ts.avg_question_score as tag_avg_score,
    ba.total_bounty,
    (hic.collaboration_events * au.Reputation * 0.01) as collaboration_weight,
    RANK() OVER (
        PARTITION BY ts.TagName 
        ORDER BY hic.total_score_impact DESC, au.Reputation DESC
    ) as impact_rank_within_tag
FROM high_impact_collaborations hic
INNER JOIN active_users au ON au.Id = hic.editor_id
INNER JOIN question_owners qo ON qo.OwnerUserId = hic.poster_id
INNER JOIN Posts p ON p.Id = qo.Id
INNER JOIN tag_stats ts ON string_to_array(
    substring(p.Tags from 2 for length(p.Tags)-2), 
    '><'
) @> ARRAY[ts.TagName]::text[]
LEFT JOIN bounty_analysis ba ON ba.PostId = p.Id
WHERE hic.total_score_impact > 100
  AND ts.avg_question_score > 2
  AND au.UpVotes > au.DownVotes
ORDER BY collaboration_weight DESC, impact_rank_within_tag
LIMIT 1000;
