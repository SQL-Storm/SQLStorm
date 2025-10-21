-- {"query": "50062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1095} 

WITH UserMetrics AS (
    -- Aggregate user-specific metrics: answer scores, badge counts, and votes given
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(ans.TotalAnswerScore, 0) AS TotalAnswerScore,
        COALESCE(ans.AnswerCount, 0) AS AnswerCount,
        COALESCE(bdg.GoldBadges, 0) AS GoldBadges,
        COALESCE(bdg.SilverBadges, 0) AS SilverBadges,
        COALESCE(bdg.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(vts.UpVotesGiven, 0) AS UpVotesGiven
    FROM
        Users u
    LEFT JOIN (
        SELECT OwnerUserId, SUM(Score) AS TotalAnswerScore, COUNT(*) AS AnswerCount
        FROM Posts
        WHERE PostTypeId = 2 AND OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ) ans ON u.Id = ans.OwnerUserId
    LEFT JOIN (
        SELECT UserId,
               SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
               SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
               SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges
        GROUP BY UserId
    ) bdg ON u.Id = bdg.UserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS UpVotesGiven
        FROM Votes
        WHERE VoteTypeId = 2 AND UserId IS NOT NULL
        GROUP BY UserId
    ) vts ON u.Id = vts.UserId
    WHERE u.Reputation > 1000
),
RankedUserContent AS (
    -- Find the most recent comment and the title of the question for the most recent answer for each user
    SELECT
        UserId,
        LastComment,
        LastAnsweredQuestionTitle
    FROM (
        SELECT
            sub.UserId,
            sub.LastComment,
            sub.LastAnsweredQuestionTitle,
            ROW_NUMBER() OVER(PARTITION BY sub.UserId ORDER BY sub.ActivityDate DESC) as rn
        FROM (
            SELECT
                c.UserId,
                c.Text AS LastComment,
                NULL AS LastAnsweredQuestionTitle,
                c.CreationDate AS ActivityDate
            FROM Comments c
            WHERE c.UserId IS NOT NULL
            UNION ALL
            SELECT
                p_ans.OwnerUserId AS UserId,
                NULL AS LastComment,
                p_ques.Title AS LastAnsweredQuestionTitle,
                p_ans.CreationDate AS ActivityDate
            FROM Posts p_ans
            JOIN Posts p_ques ON p_ans.ParentId = p_ques.Id
            WHERE p_ans.PostTypeId = 2 AND p_ans.OwnerUserId IS NOT NULL
        ) sub
    ) ranked
    WHERE rn = 1
),
EngagementScores AS (
    -- Calculate a composite engagement score for each user
    SELECT
        m.UserId,
        m.DisplayName,
        m.Reputation,
        EXTRACT(YEAR FROM m.CreationDate) AS JoinYear,
        m.TotalAnswerScore,
        m.AnswerCount,
        m.GoldBadges,
        m.SilverBadges,
        m.UpVotesGiven,
        c.LastComment,
        c.LastAnsweredQuestionTitle,
        -- Weighted score calculation
        (m.Reputation * 0.2) +
        (m.TotalAnswerScore * 1.5) +
        (m.GoldBadges * 100) +
        (m.SilverBadges * 25) +
        (m.UpVotesGiven * 0.1) +
        (m.AnswerCount * 2) AS EngagementScore
    FROM UserMetrics m
    LEFT JOIN RankedUserContent c ON m.UserId = c.UserId
)
-- Final selection: Rank users by their engagement score for each year they joined and select the top 5
SELECT
    JoinYear,
    DisplayName,
    Reputation,
    CAST(EngagementScore AS BIGINT) AS EngagementScore,
    YearlyRank,
    TotalAnswerScore,
    AnswerCount,
    GoldBadges,
    SilverBadges,
    LastComment,
    LastAnsweredQuestionTitle
FROM (
    SELECT
        *,
        DENSE_RANK() OVER (PARTITION BY JoinYear ORDER BY EngagementScore DESC) as YearlyRank
    FROM EngagementScores
    WHERE JoinYear >= EXTRACT(YEAR FROM CURRENT_DATE) - 10
) AS FinalRankedUsers
WHERE YearlyRank <= 5
ORDER BY JoinYear DESC, YearlyRank ASC, Reputation DESC;
