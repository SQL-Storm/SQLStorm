-- {"query": "3797.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2681} 

WITH
    top_users AS (
        SELECT u.Id,
               u.DisplayName,
               u.Reputation,
               u.CreationDate,
               u.LastAccessDate,
               COALESCE(u.Location, 'Unknown') AS Location,
               ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank
        FROM Users u
        WHERE u.Reputation > 1000
    ),
    user_post_counts AS (
        SELECT p.OwnerUserId AS UserId,
               COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
               COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
               SUM(p.Score) FILTER (WHERE p.PostTypeId = 1) AS QuestionScoreSum,
               SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AnswerScoreSum,
               MAX(p.CreationDate) AS LastPostDate
        FROM Posts p
        GROUP BY p.OwnerUserId
    ),
    user_badge_summary AS (
        SELECT b.UserId,
               COUNT(*) AS TotalBadges,
               COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
               COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
               COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
               STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 3) AS BronzeNames
        FROM Badges b
        GROUP BY b.UserId
    ),
    recent_question AS (
        SELECT p.OwnerUserId,
               p.Id AS RecentQuestionId,
               p.Title,
               p.CreationDate,
               ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),
    tag_usage AS (
        SELECT u.Id AS UserId,
               UNNEST(string_to_array(TRIM(BOTH '><' FROM p.Tags), '><')) AS Tag,
               COUNT(*) AS TagCount
        FROM top_users u
        JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
        WHERE p.Tags IS NOT NULL
        GROUP BY u.Id, Tag
    ),
    top_tags_per_user AS (
        SELECT tu.UserId,
               STRING_AGG(tu.Tag, ', ') FILTER (WHERE tu.rnk <= 5) AS Top5Tags
        FROM (
            SELECT t.UserId,
                   t.Tag,
                   ROW_NUMBER() OVER (PARTITION BY t.UserId ORDER BY t.TagCount DESC) AS rnk
            FROM tag_usage t
        ) tu
        GROUP BY tu.UserId
    )
SELECT
    tu.Id                              AS UserId,
    tu.DisplayName                     AS DisplayName,
    tu.Reputation                      AS Reputation,
    tu.rep_rank                        AS RankByReputation,
    COALESCE(upc.QuestionCount,0)      AS QuestionsPosted,
    COALESCE(upc.AnswerCount,0)        AS AnswersPosted,
    COALESCE(upc.QuestionScoreSum,0)   AS QuestionScoreSum,
    COALESCE(upc.AnswerScoreSum,0)     AS AnswerScoreSum,
    COALESCE(ub.TotalBadges,0)         AS TotalBadges,
    COALESCE(ub.GoldBadges,0)          AS GoldBadges,
    COALESCE(ub.SilverBadges,0)        AS SilverBadges,
    COALESCE(ub.BronzeBadges,0)        AS BronzeBadges,
    ub.BronzeNames                     AS BronzeBadgeNames,
    rq.Title                           AS RecentQuestionTitle,
    rq.CreationDate                    AS RecentQuestionDate,
    tt.Top5Tags                        AS Top5Tags,
    CASE
        WHEN upc.LastPostDate IS NULL               THEN 'Never'
        WHEN upc.LastPostDate > CURRENT_DATE - INTERVAL '30 days' THEN 'Active'
        ELSE 'Dormant'
    END                                 AS ActivityStatus
FROM top_users tu
LEFT JOIN user_post_counts upc      ON upc.UserId = tu.Id
LEFT JOIN user_badge_summary ub    ON ub.UserId = tu.Id
LEFT JOIN (
    SELECT OwnerUserId, Title, CreationDate
    FROM recent_question
    WHERE rn = 1
) rq                               ON rq.OwnerUserId = tu.Id
LEFT JOIN top_tags_per_user tt    ON tt.UserId = tu.Id
WHERE tu.rep_rank <= 100
ORDER BY tu.Reputation DESC
LIMIT 100

UNION ALL

SELECT
    NULL                               AS UserId,
    '--- Summary ---'                  AS DisplayName,
    NULL                               AS Reputation,
    NULL                               AS RankByReputation,
    SUM(COALESCE(upc.QuestionCount,0)) AS QuestionsPosted,
    SUM(COALESCE(upc.AnswerCount,0))   AS AnswersPosted,
    SUM(COALESCE(upc.QuestionScoreSum,0)) AS QuestionScoreSum,
    SUM(COALESCE(upc.AnswerScoreSum,0))   AS AnswerScoreSum,
    SUM(COALESCE(ub.TotalBadges,0))    AS TotalBadges,
    SUM(COALESCE(ub.GoldBadges,0))     AS GoldBadges,
    SUM(COALESCE(ub.SilverBadges,0))   AS SilverBadges,
    SUM(COALESCE(ub.BronzeBadges,0))   AS BronzeBadges,
    NULL                               AS BronzeBadgeNames,
    NULL                               AS RecentQuestionTitle,
    NULL                               AS RecentQuestionDate,
    NULL                               AS Top5Tags,
    NULL                               AS ActivityStatus
FROM top_users tu
LEFT JOIN user_post_counts upc ON upc.UserId = tu.Id
LEFT JOIN user_badge_summary ub ON ub.UserId = tu.Id
WHERE tu.rep_rank <= 100;
