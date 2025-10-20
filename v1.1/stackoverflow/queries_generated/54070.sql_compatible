WITH
    question_tags AS (
        SELECT p.OwnerUserId,
               p.Id AS QuestionId,
               string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags) - 2), '><') AS tag_arr
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),
    expanded_tags AS (
        SELECT qt.OwnerUserId,
               UNNEST(qt.tag_arr) AS tag
        FROM question_tags qt
    ),
    question_upvotes AS (
        SELECT p.OwnerUserId,
               COUNT(*) AS upvote_count
        FROM Votes v
        JOIN Posts p ON v.PostId = p.Id
        WHERE p.PostTypeId = 1
          AND v.VoteTypeId = 2
        GROUP BY p.OwnerUserId
    ),
    bounties_started AS (
        SELECT v.UserId,
               SUM(v.BountyAmount) AS bounty_sum
        FROM Votes v
        WHERE v.VoteTypeId = 8
        GROUP BY v.UserId
    ),
    duplicates_per_user AS (
        SELECT p.OwnerUserId,
               COUNT(*) AS dup_count
        FROM PostLinks pl
        JOIN Posts p ON pl.PostId = p.Id
        WHERE pl.LinkTypeId = 3
        GROUP BY p.OwnerUserId
    ),
    closed_questions AS (
        SELECT p.OwnerUserId,
               COUNT(*) AS closed_count
        FROM PostHistory ph
        JOIN Posts p ON ph.PostId = p.Id
        WHERE ph.PostHistoryTypeId = 10
          AND p.PostTypeId = 1
        GROUP BY p.OwnerUserId
    ),
    avg_scores AS (
        SELECT p.OwnerUserId,
               AVG(p.Score) AS avg_score
        FROM Posts p
        WHERE p.PostTypeId = 1
        GROUP BY p.OwnerUserId
    ),
    user_agg AS (
        SELECT u.Id AS UserId,
               u.Reputation,
               COALESCE(question_upvotes.upvote_count, 0) AS upvotes_received,
               COALESCE(bounties_started.bounty_sum, 0) AS bounty_started,
               COALESCE(duplicates_per_user.dup_count, 0) AS dup_count,
               COALESCE(closed_questions.closed_count, 0) AS closed_count,
               COALESCE(avg_scores.avg_score, 0) AS avg_question_score
        FROM Users u
        LEFT JOIN question_upvotes ON u.Id = question_upvotes.OwnerUserId
        LEFT JOIN bounties_started ON u.Id = bounties_started.UserId
        LEFT JOIN duplicates_per_user ON u.Id = duplicates_per_user.OwnerUserId
        LEFT JOIN closed_questions ON u.Id = closed_questions.OwnerUserId
        LEFT JOIN avg_scores ON u.Id = avg_scores.OwnerUserId
    ),
    ranked_users AS (
        SELECT ua.UserId,
               ua.Reputation,
               ua.upvotes_received,
               ua.bounty_started,
               ua.dup_count,
               ua.closed_count,
               ua.avg_question_score,
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
GROUP BY ru.rank,
         u.DisplayName,
         ru.Reputation,
         ru.upvotes_received,
         ru.bounty_started,
         ru.dup_count,
         ru.closed_count,
         ru.avg_question_score,
         ru.composite_score,
         ru.UserId
ORDER BY ru.rank
LIMIT 20;