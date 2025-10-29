-- {"query": "3574.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1447}
WITH top_users AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(bc.badge_cnt, 0)          AS badge_cnt,
           COALESCE(asw.answer_cnt, 0)       AS answer_cnt,
           COALESCE(asw.avg_score, 0)        AS avg_score,
           COALESCE(ts.tags_list, '')        AS tags_list,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COALESCE(bc.badge_cnt,0) DESC) AS rn
    FROM Users u
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS badge_cnt
        FROM Badges
        GROUP BY UserId
    ) bc ON bc.UserId = u.Id
    LEFT JOIN (
        SELECT p.OwnerUserId,
               COUNT(*) AS answer_cnt,
               AVG(CAST(p.Score AS DECIMAL(10,2))) AS avg_score
        FROM Posts p
        WHERE p.PostTypeId = 2
          AND p.Id IN (SELECT AcceptedAnswerId FROM Posts WHERE AcceptedAnswerId IS NOT NULL)
        GROUP BY p.OwnerUserId
    ) asw ON asw.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT a.OwnerUserId,
               STRING_AGG(DISTINCT tg.tag, ', ') AS tags_list
        FROM Posts a
        JOIN LATERAL (
            SELECT UNNEST(STRING_TO_ARRAY(TRIM(BOTH '><' FROM a.Tags), '><')) AS tag
        ) tg ON TRUE
        JOIN Tags t ON t.TagName = tg.tag
        WHERE a.PostTypeId = 2
        GROUP BY a.OwnerUserId
    ) ts ON ts.OwnerUserId = u.Id
    WHERE u.Reputation > 1000
)
SELECT tu.Id,
       tu.DisplayName,
       tu.Reputation,
       tu.badge_cnt,
       tu.answer_cnt,
       tu.avg_score,
       tu.tags_list,
       COALESCE(vs.up_votes, 0)   AS up_votes,
       COALESCE(vs.down_votes, 0) AS down_votes,
       CASE
           WHEN tu.avg_score IS NULL THEN 'No answers'
           WHEN tu.avg_score >= 5 THEN 'High quality'
           ELSE 'Average'
       END AS quality_tier
FROM top_users tu
LEFT JOIN (
    SELECT p.OwnerUserId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
) vs ON vs.OwnerUserId = tu.Id
WHERE tu.rn <= 10
GROUP BY
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.badge_cnt,
    tu.answer_cnt,
    tu.avg_score,
    tu.tags_list,
    vs.up_votes,
    vs.down_votes,
    tu.rn
ORDER BY tu.Reputation DESC, tu.badge_cnt DESC;