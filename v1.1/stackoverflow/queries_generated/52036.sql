-- {"query": "52036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 408} 

WITH TagAnswers AS (
    SELECT p.ParentId as question_id, p.OwnerUserId, p.Score,
           string_to_array(substring(q.Tags, 2, length(q.Tags)-2), ''><'') as tags
    FROM Posts p
    JOIN Posts q ON p.ParentId = q.Id
    WHERE p.PostTypeId = 2 AND q.PostTypeId = 1 AND q.Tags IS NOT NULL
),
UnnestedTags AS (
    SELECT ta.question_id, ta.OwnerUserId, ta.Score, unnest(ta.tags) as tag
    FROM TagAnswers ta
),
TagUserStats AS (
    SELECT tag, OwnerUserId, COUNT(*) as num_answers, AVG(Score) as avg_score, SUM(Score) as total_score
    FROM UnnestedTags
    GROUP BY tag, OwnerUserId
    HAVING COUNT(*) > 5
),
TopUsersPerTag AS (
    SELECT tag, OwnerUserId, num_answers, avg_score, total_score,
           RANK() OVER (PARTITION BY tag ORDER BY num_answers DESC, avg_score DESC, total_score DESC) as rank
    FROM TagUserStats
),
UserDetails AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate,
           COUNT(DISTINCT b.Id) as badges,
           COUNT(DISTINCT c.Id) as comments
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
)
SELECT tpt.tag, ud.DisplayName, tpt.num_answers, tpt.avg_score, tpt.total_score, ud.Reputation, ud.badges, ud.comments
FROM TopUsersPerTag tpt
JOIN UserDetails ud ON tpt.OwnerUserId = ud.Id
WHERE rank <= 10
ORDER BY tag, rank
