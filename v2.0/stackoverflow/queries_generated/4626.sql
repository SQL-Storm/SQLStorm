-- {"query": "4626.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1279} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn_user_posts,
        RANK() OVER (ORDER BY p.Score DESC) as rnk_score,
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId) as total_score_per_user,
        AVG(CAST(p.AnswerCount AS DECIMAL(10, 2))) OVER (PARTITION BY p.PostTypeId) as avg_answer_count_by_type
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
UserPostStats AS (
    SELECT
        up.OwnerUserId,
        COUNT(up.PostId) AS num_posts,
        SUM(up.total_score_per_user) AS total_user_score,
        MAX(CASE WHEN up.rn_user_posts = 1 THEN up.Title ELSE NULL END) AS latest_post_title,
        AVG(CAST(up.Score AS DECIMAL(10,2))) AS average_post_score,
        SUM(CASE WHEN up.Score > 100 THEN 1 ELSE 0 END) AS high_score_post_count,
        MAX(up.avg_answer_count_by_type) AS max_avg_answer_count_overall
    FROM RankedPosts up
    GROUP BY up.OwnerUserId
),
TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(ups.num_posts, 0) AS total_posts_authored,
        COALESCE(ups.total_user_score, 0) AS accumulated_score,
        ups.latest_post_title,
        ups.average_post_score,
        ups.high_score_post_count,
        ups.max_avg_answer_count_overall,
        COUNT(b.Id) AS num_badges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges
    FROM Users u
    LEFT JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000 -- Filter for users with significant reputation
    GROUP BY u.Id, u.DisplayName, u.Reputation, ups.num_posts, ups.total_user_score, ups.latest_post_title, ups.average_post_score, ups.high_score_post_count, ups.max_avg_answer_count_overall
    HAVING COUNT(b.Id) > 5 -- Users with at least 5 badges
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.total_posts_authored,
    tu.accumulated_score,
    tu.latest_post_title,
    tu.average_post_score,
    tu.high_score_post_count,
    tu.num_badges,
    tu.gold_badges,
    tu.silver_badges,
    tu.bronze_badges,
    rp.Title AS HighestRankedPostTitle,
    rp.Score AS HighestRankedPostScore,
    CASE
        WHEN tu.average_post_score > tu.max_avg_answer_count_overall THEN 'Above Average Answer Count Type'
        WHEN tu.average_post_score < tu.max_avg_answer_count_overall THEN 'Below Average Answer Count Type'
        ELSE 'On Par Average Answer Count Type'
    END AS ScoreVsAvgAnswerCategory,
    UPPER(LEFT(tu.DisplayName, 3)) || '*' AS ProcessedDisplayName,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = tu.UserId AND c.Score > 5) AS FrequentCommenterCount
FROM TopUsers tu
JOIN RankedPosts rp ON tu.UserId = rp.OwnerUserId AND rp.rn_user_posts = 1
LEFT JOIN PostLinks pl ON tu.UserId = pl.PostId
WHERE tu.Reputation BETWEEN 5000 AND 50000
  AND tu.average_post_score IS NOT NULL
  AND tu.total_posts_authored > 10
  AND (pl.LinkTypeId = 3 OR pl.LinkTypeId IS NULL) -- Include users with no duplicate links or who are the source of a duplicate link
GROUP BY
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.total_posts_authored,
    tu.accumulated_score,
    tu.latest_post_title,
    tu.average_post_score,
    tu.high_score_post_count,
    tu.num_badges,
    tu.gold_badges,
    tu.silver_badges,
    tu.bronze_badges,
    rp.Title,
    rp.Score,
    tu.max_avg_answer_count_overall
HAVING COUNT(pl.Id) < 50 -- Limit users with excessive post links
ORDER BY tu.Reputation DESC, tu.accumulated_score DESC
LIMIT 100;
