-- {"query": "52098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 735} 
WITH TagStats AS (
    SELECT 
        tag,
        COUNT(*) AS question_count,
        AVG(p.Score) AS avg_score,
        SUM(p.AnswerCount) AS total_answers
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= '2013-01-01'
    GROUP BY tag
    HAVING COUNT(*) > 1000
),
UserTagContributions AS (
    SELECT 
        p.OwnerUserId AS UserId,
        t.tag,
        COUNT(p.Id) AS posts_in_tag,
        SUM(p.Score) AS total_score_in_tag,
        AVG(p.Score) AS avg_score_in_tag
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(tag)
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= '2013-01-01'
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, t.tag
),
UserMetrics AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS total_questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS total_answers,
        SUM(p.Score) AS total_score,
        AVG(p.Score) AS avg_score,
        COUNT(DISTINCT c.Id) AS total_comments,
        COUNT(DISTINCT b.Id) AS total_badges,
        COUNT(DISTINCT v.Id) AS total_votes_received,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS net_votes
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.CreationDate
),
RankedTags AS (
    SELECT 
        tag,
        ROW_NUMBER() OVER (ORDER BY question_count DESC) AS rank
    FROM TagStats
),
TopUsers AS (
    SELECT 
        ut.UserId,
        rt.tag,
        ut.posts_in_tag,
        ut.total_score_in_tag,
        ROW_NUMBER() OVER (PARTITION BY rt.tag ORDER BY ut.total_score_in_tag DESC) AS user_rank_in_tag
    FROM UserTagContributions ut
    JOIN RankedTags rt ON ut.tag = rt.tag
    WHERE rt.rank <= 10
)
SELECT 
    tu.UserId,
    u.DisplayName,
    tu.tag,
    um.Reputation,
    tu.posts_in_tag,
    tu.total_score_in_tag,
    um.total_posts,
    um.total_answers,
    um.avg_score,
    um.total_badges,
    um.net_votes
FROM TopUsers tu
JOIN Users u ON tu.UserId = u.Id
JOIN UserMetrics um ON tu.UserId = um.Id
WHERE tu.user_rank_in_tag <= 5
ORDER BY tu.tag, tu.total_score_in_tag DESC;