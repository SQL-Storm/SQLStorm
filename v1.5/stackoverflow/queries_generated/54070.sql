-- {"query": "54070.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 4605} 
WITH
    -- Extract tags for each question and expand into rows per tag
    question_tags AS (
        SELECT p.OwnerUserId,
               p.Id AS QuestionId,
               string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><') AS tag_arr
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),
    expanded_tags AS (
        SELECT qt.OwnerUserId,
               UNNEST(qt.tag_arr) AS tag
        FROM question_tags qt
    ),
    -- Count upvotes received by each user on their questions
    question_upvotes AS (
        SELECT p.OwnerUserId,
               COUNT(*) AS upvote_count
        FROM Votes v
        JOIN Posts p ON v.PostId = p.Id
        WHERE p.PostTypeId = 1
          AND v.VoteTypeId = 2
        GROUP BY p.OwnerUserId
    ),
    -- Sum of bounty amounts started by each user
    bounties_started AS (
        SELECT v.UserId,
               SUM(v.BountyAmount) AS bounty_sum
        FROM Votes v
        WHERE v.VoteTypeId = 8
        GROUP BY v.UserId
    ),
    -- Number of duplicate posts per user
    duplicates_per_user AS (
        SELECT p.OwnerUserId,
               COUNT(*) AS dup_count
        FROM PostLinks pl
        JOIN Posts p ON pl.PostId = p.Id
        WHERE pl.LinkTypeId = 3
        GROUP BY p.OwnerUserId
    ),
    -- Closed question counts per user
    closed_questions AS (
        SELECT p.OwnerUserId,
               COUNT(*) AS closed_count
        FROM PostHistory ph
        JOIN Posts p ON ph.PostId = p.Id
        WHERE ph.PostHistoryTypeId = 10
          AND p.PostTypeId = 1
        GROUP BY p.OwnerUserId
    ),
    -- Average score of questions per user
    avg_scores AS (
        SELECT p.OwnerUserId,
               AVG(p.Score) AS avg_score
        FROM Posts p
        WHERE p.PostTypeId = 1
        GROUP BY p.OwnerUserId
    ),
    -- Aggregate per user
    user_agg AS (
        SELECT u.Id AS UserId,
               u.Reputation,
               COALESCE(qu.upvote_count, 0) AS upvotes_received,
               COALESCE(bs.bounty_sum, 0) AS bounty_started,
               COALESCE(dp.dup_count, 0) AS dup_count,
               COALESCE(cq.closed_count, 0) AS closed_count,
               COALESCE(ascore.avg_score, 0) AS avg_question_score
        FROM Users u
        LEFT JOIN question_upvotes qv ON u.Id = qv.OwnerUserId
        LEFT JOIN bounties_started bs ON u.Id = bs.UserId
        LEFT JOIN duplicates_per_user dp ON u.Id = dp.OwnerUserId
        LEFT JOIN closed_questions cq ON u.Id = cq.OwnerUserId
        LEFT JOIN avg_scores ascore ON u.Id = ascore.OwnerUserId
    ),
    -- Compute composite score and rank users
    ranked_users AS (
        SELECT ua.*,
               (ua.Reputation * 0.4
                + ua.upvotes_received * 0.3
                + ua.bounty_started * 0.1
                - ua.dup_count * 0.05
                - ua.closed_count * 0.05
                + ua.avg_question_score * 0.1) AS composite_score,
               ROW_NUMBER() OVER (ORDER BY
                    (ua.Reputation * 0.4
                     + ua.upvotes_received * 0.3
                     + ua.bounty_started * 0.1
                     - ua.dup_count * 0.05
                     - ua.closed_count * 0.05
                     + ua.avg_question_score * 0.1) DESC) AS rank
        FROM user_agg ua
    )
SELECT ru.rank,
       u.DisplayName,
       ru.Reputation,
       ru.upvotes_received,
       ru.bounty_started,
       ru.dup_count,
       ru.closed_count,
       ru.avg_question_score,
       ru.composite_score,
       STRING_AGG(DISTINCT et.tag, ', ') AS tags
FROM ranked_users ru
JOIN Users u ON u.Id = ru.UserId
LEFT JOIN expanded_tags et ON et.OwnerUserId = ru.UserId
GROUP BY ru.rank, u.DisplayName, ru.Reputation, ru.upvotes_received,
         ru.bounty_started, ru.dup_count, ru.closed_count, ru.avg_question_score,
         ru.composite_score
ORDER BY ru.rank
LIMIT 20;