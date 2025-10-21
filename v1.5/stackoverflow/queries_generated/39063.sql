-- {"query": "39063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 1895} 

WITH TagUsage AS (
    SELECT
        t.TagName,
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS Questions,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS Answers
    FROM Posts p
    CROSS JOIN LATERAL
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag(tag_name)
    JOIN Tags t
      ON t.TagName = tag.tag_name
    GROUP BY
        t.TagName,
        p.OwnerUserId
),
VoteStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Posts p
    LEFT JOIN Votes v
      ON v.PostId = p.Id
    GROUP BY
        p.OwnerUserId
),
BadgeStats AS (
    SELECT
        b.UserId,
        json_agg(json_build_object('BadgeName', b.Name, 'Count', COUNT(*))) AS Badges
    FROM Badges b
    GROUP BY
        b.UserId
),
AnswerTimes AS (
    SELECT
        p.OwnerUserId AS QuestionerId,
        AVG(EXTRACT(EPOCH FROM (a.CreationDate - p.CreationDate))) / 86400.0 AS AvgAnswerDelayDays
    FROM Posts p
    JOIN Posts a
      ON a.ParentId = p.Id
     AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
    GROUP BY
        p.OwnerUserId
),
TopContributors AS (
    SELECT
        tu.TagName,
        tu.UserId,
        ROW_NUMBER() OVER (PARTITION BY tu.TagName ORDER BY vs.UpVotes DESC NULLS LAST) AS Rank
    FROM TagUsage tu
    JOIN VoteStats vs
      ON vs.UserId = tu.UserId
)
SELECT
    tc.TagName,
    u.DisplayName,
    tu.Questions,
    tu.Answers,
    vs.UpVotes,
    vs.DownVotes,
    at.AvgAnswerDelayDays,
    bs.Badges,
    tc.Rank
FROM TopContributors tc
JOIN TagUsage tu
  ON tu.TagName = tc.TagName
 AND tu.UserId = tc.UserId
JOIN VoteStats vs
  ON vs.UserId = tc.UserId
LEFT JOIN AnswerTimes at
  ON at.QuestionerId = tc.UserId
LEFT JOIN BadgeStats bs
  ON bs.UserId = tc.UserId
JOIN Users u
  ON u.Id = tc.UserId
WHERE tc.Rank <= 5
ORDER BY
    tc.TagName,
    tc.Rank;
