-- {"query": "20088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1958} 

WITH UserAnswerMetrics AS (
    -- Calculate detailed metrics for each answer provided by a user, including time-to-answer and ranking within a question.
    SELECT
        p_ans.OwnerUserId,
        p_ans.Id AS AnswerId,
        p_ques.Id AS QuestionId,
        p_ans.Score AS AnswerScore,
        p_ques.Tags,
        CASE WHEN p_ques.AcceptedAnswerId = p_ans.Id THEN 1 ELSE 0 END AS IsAcceptedAnswer,
        (p_ans.CreationDate - p_ques.CreationDate) AS TimeToAnswer,
        -- Rank answers by score for each question to see who provides the best answers
        RANK() OVER(PARTITION BY p_ques.Id ORDER BY p_ans.Score DESC, p_ans.CreationDate ASC) as AnswerRank,
        -- Get the score of the chronologically previous answer to the same question to analyze answering dynamics
        LAG(p_ans.Score, 1, 0) OVER(PARTITION BY p_ques.Id ORDER BY p_ans.CreationDate ASC) as PreviousAnswerScore
    FROM Posts p_ans
    INNER JOIN Posts p_ques ON p_ans.ParentId = p_ques.Id
    WHERE p_ans.PostTypeId = 2 -- Answers
      AND p_ans.OwnerUserId IS NOT NULL
      AND p_ques.ClosedDate IS NULL
      AND p_ans.CreationDate > '2020-01-01' -- Focus on recent activity
),
UserAggregatedStats AS (
    -- Aggregate answer metrics and join with user and badge information to build a comprehensive user profile.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.AboutMe,
        COUNT(uam.AnswerId) AS TotalAnswers,
        SUM(uam.AnswerScore) AS TotalAnswerScore,
        SUM(uam.IsAcceptedAnswer) AS AcceptedAnswers,
        AVG(uam.AnswerScore) AS AvgAnswerScore,
        AVG(EXTRACT(EPOCH FROM uam.TimeToAnswer)) / 3600.0 AS AvgHoursToAnswer,
        -- Count Gold, Silver, Bronze badges using conditional aggregation
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        -- Correlated subquery: Get the date of the user's last content-modifying activity (edit or comment)
        (SELECT MAX(ActivityDate) FROM (
            SELECT MAX(ph.CreationDate) AS ActivityDate FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
            UNION ALL
            SELECT MAX(c.CreationDate) AS ActivityDate FROM Comments c WHERE c.UserId = u.Id
        ) AS LastActivity) AS LastActivityDate
    FROM Users u
    LEFT JOIN UserAnswerMetrics uam ON u.Id = uam.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 5000 AND u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.AboutMe
    HAVING COUNT(uam.AnswerId) > 10 OR SUM(CASE WHEN b.Class = 1 THEN 1 END) > 0
),
UserTopTag AS (
    -- Determine the primary tag each user is active in by unnesting tags and analyzing answer scores.
    SELECT
        OwnerUserId,
        Tag,
        TotalTagScore,
        -- Find the top tag for each user based on their cumulative answer score in that tag
        ROW_NUMBER() OVER(PARTITION BY OwnerUserId ORDER BY TotalTagScore DESC, AnswerCount DESC) as rn
    FROM (
        SELECT
            p.OwnerUserId,
            unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS Tag,
            SUM(p.Score) as TotalTagScore,
            COUNT(*) as AnswerCount
        FROM Posts p
        INNER JOIN Posts q ON p.ParentId = q.Id
        WHERE p.PostTypeId = 2 AND p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId, Tag
    ) AS TagStats
)
-- Final SELECT statement combining all data, calculating a custom score, and categorizing users.
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalAnswers,
    uas.AcceptedAnswers,
    COALESCE(uas.TotalAnswerScore, 0) AS TotalAnswerScore,
    uas.AvgAnswerScore,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    utt.Tag AS PrimaryTag,
    -- Complex calculated "Influence Score" to rank users based on a weighted formula of their contributions.
    (uas.Reputation * 0.1) + (uas.TotalAnswerScore * 0.4) + (uas.AcceptedAnswers * 25) + (uas.GoldBadges * 100) + (uas.SilverBadges * 25) - (EXTRACT(YEAR FROM AGE(NOW(), uas.UserCreationDate)) * 50) AS InfluenceScore,
    -- Categorize user based on their activity profile using a complex CASE statement.
    CASE
        WHEN uas.AcceptedAnswers > uas.TotalAnswers * 0.4 AND uas.AvgHoursToAnswer < 24 THEN 'Ace Responder'
        WHEN uas.GoldBadges > 5 AND uas.Reputation > 100000 THEN 'Community Pillar'
        WHEN uas.AvgHoursToAnswer < 6 THEN 'Quick Draw'
        WHEN (SELECT COUNT(*) FROM Comments c WHERE c.UserId = uas.UserId) > uas.TotalAnswers * 3 THEN 'Dedicated Commenter'
        WHEN uas.AboutMe LIKE '%expert%' OR uas.AboutMe LIKE '%PhD%' THEN 'Verified Expert'
        ELSE 'Valued Contributor'
    END AS UserCategory,
    -- String manipulation to create a profile summary.
    CONCAT(
        'User ''', uas.DisplayName, ''' (', uas.UserId, ') has a reputation of ', uas.Reputation,
        '. Primarily active in the ''', COALESCE(utt.Tag, 'General'), ''' tag. Last active on: ', TO_CHAR(uas.LastActivityDate, 'YYYY-MM-DD')
    ) AS ProfileSummary
FROM UserAggregatedStats uas
LEFT JOIN UserTopTag utt ON uas.UserId = utt.OwnerUserId AND utt.rn = 1
WHERE uas.LastActivityDate IS NOT NULL OR uas.TotalAnswers > 100

UNION ALL

-- Find users with a single, highly-voted answer but low overall activity ("One-Hit Wonders").
SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    1,
    CASE WHEN p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END,
    p.Score,
    p.Score,
    0, 0, 0,
    unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')),
    p.Score * 5.0 AS InfluenceScore,
    'One-Hit Wonder' AS UserCategory,
    CONCAT('User ''', u.DisplayName, ''' has a single high-scoring (', p.Score, ') answer.') AS ProfileSummary
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
JOIN Posts q ON p.ParentId = q.Id
WHERE p.PostTypeId = 2
  AND p.Score > 300
  AND p.CreationDate > '2018-01-01'
  AND u.Reputation < 15000
  AND NOT EXISTS (
      -- Ensure they don't have many other answers, making them a true one-hit wonder.
      SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.Id != p.Id AND p2.PostTypeId = 2 AND p2.Score > 10
  )

ORDER BY InfluenceScore DESC, Reputation DESC
LIMIT 500;
