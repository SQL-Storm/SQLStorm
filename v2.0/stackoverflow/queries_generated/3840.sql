-- {"query": "3840.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2020} 
WITH recent_answers AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.Title,
        p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.CreationDate >= (CURRENT_DATE - INTERVAL '1 year')
),
tag_counts AS (
    SELECT
        ra.OwnerUserId,
        COUNT(DISTINCT TRIM(t)) AS distinct_tags
    FROM recent_answers ra
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(ra.Tags, 2, LENGTH(ra.Tags) - 2), '><')) AS t
    ) taglist
    WHERE ra.Tags IS NOT NULL
    GROUP BY ra.OwnerUserId
),
user_badges AS (
    SELECT
        UserId,
        COUNT(*) AS total_badges,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS gold_badges
    FROM Badges
    GROUP BY UserId
),
answer_stats AS (
    SELECT
        OwnerUserId,
        COUNT(*) AS answer_cnt,
        AVG(Score) AS avg_score,
        MAX(CreationDate) AS latest_answer_date
    FROM recent_answers
    GROUP BY OwnerUserId
),
latest_answer_title AS (
    SELECT
        ra.OwnerUserId,
        ra.Title AS latest_title,
        LEFT(ra.Title, 50) AS truncated_title
    FROM recent_answers ra
    WHERE (ra.OwnerUserId, ra.CreationDate) IN (
        SELECT OwnerUserId, MAX(CreationDate)
        FROM recent_answers
        GROUP BY OwnerUserId
    )
),
vote_agg AS (
    SELECT
        p.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(asr.answer_cnt, 0) AS AnswerCount,
    COALESCE(asr.avg_score, 0) AS AvgScore,
    COALESCE(tc.distinct_tags, 0) AS DistinctTagsAnswered,
    COALESCE(ub.total_badges, 0) AS TotalBadges,
    COALESCE(ub.gold_badges, 0) AS GoldBadges,
    COALESCE(vu.upvotes, 0) AS TotalUpVotesReceived,
    COALESCE(vu.downvotes, 0) AS TotalDownVotesReceived,
    COALESCE(lat.latest_title, '') AS LatestAnswerTitle,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COALESCE(asr.answer_cnt, 0) DESC) AS ReputationRank
FROM Users u
LEFT JOIN answer_stats asr ON u.Id = asr.OwnerUserId
LEFT JOIN tag_counts tc ON u.Id = tc.OwnerUserId
LEFT JOIN user_badges ub ON u.Id = ub.UserId
LEFT JOIN vote_agg vu ON u.Id = vu.OwnerUserId
LEFT JOIN latest_answer_title lat ON u.Id = lat.OwnerUserId
WHERE u.Reputation > 10000
  AND (asr.answer_cnt IS NOT NULL OR ub.total_badges > 0)

UNION ALL

SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    0 AS AnswerCount,
    0 AS AvgScore,
    0 AS DistinctTagsAnswered,
    COALESCE(ub.total_badges, 0) AS TotalBadges,
    COALESCE(ub.gold_badges, 0) AS GoldBadges,
    0 AS TotalUpVotesReceived,
    0 AS TotalDownVotesReceived,
    NULL AS LatestAnswerTitle,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
FROM Users u
LEFT JOIN user_badges ub ON u.Id = ub.UserId
WHERE u.Reputation > 20000
  AND NOT EXISTS (
      SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2
  )
ORDER BY ReputationRank
LIMIT 20;