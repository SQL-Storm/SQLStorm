-- {"query": "50045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1594} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(p_counts.QuestionCount, 0) AS QuestionCount,
        COALESCE(p_counts.AnswerCount, 0) AS AnswerCount,
        COALESCE(p_counts.AvgAnswerScore, 0.0) AS AvgAnswerScore,
        COALESCE(p_counts.TotalViews, 0) AS TotalViewsOnQuestions,
        COALESCE(b_counts.GoldBadges, 0) AS GoldBadges,
        COALESCE(b_counts.SilverBadges, 0) AS SilverBadges,
        COALESCE(b_counts.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(acc_ans.AcceptedAnswerCount, 0) AS AcceptedAnswerCount,
        COALESCE(c_counts.CommentCount, 0) AS CommentCount,
        COALESCE(v_counts.UpVotesCast, 0) AS UpVotesCast,
        COALESCE(v_counts.DownVotesCast, 0) AS DownVotesCast
    FROM
        Users u
    LEFT JOIN (
        SELECT
            OwnerUserId,
            SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
            SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
            AVG(CASE WHEN PostTypeId = 2 THEN Score ELSE NULL END) AS AvgAnswerScore,
            SUM(CASE WHEN PostTypeId = 1 THEN ViewCount ELSE 0 END) AS TotalViews
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ) AS p_counts ON u.Id = p_counts.OwnerUserId
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges
        GROUP BY UserId
    ) AS b_counts ON u.Id = b_counts.UserId
    LEFT JOIN (
        SELECT p_ans.OwnerUserId, COUNT(*) AS AcceptedAnswerCount
        FROM Posts p_q
        JOIN Posts p_ans ON p_q.AcceptedAnswerId = p_ans.Id
        WHERE p_ans.OwnerUserId IS NOT NULL AND p_q.PostTypeId = 1 AND p_ans.PostTypeId = 2
        GROUP BY p_ans.OwnerUserId
    ) AS acc_ans ON u.Id = acc_ans.OwnerUserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS CommentCount FROM Comments WHERE UserId IS NOT NULL GROUP BY UserId
    ) AS c_counts ON u.Id = c_counts.UserId
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCast,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCast
        FROM Votes
        WHERE UserId IS NOT NULL
        GROUP BY UserId
    ) AS v_counts ON u.Id = v_counts.UserId
    WHERE u.Reputation > 1000
),
UserScoreCalculation AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        CreationDate,
        QuestionCount,
        AnswerCount,
        AvgAnswerScore,
        AcceptedAnswerCount,
        TotalViewsOnQuestions,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        CommentCount,
        -- A complex, arbitrary scoring metric for benchmarking
        (
            (Reputation * 0.1) +
            (AcceptedAnswerCount * 25) +
            (AnswerCount * 2) +
            (QuestionCount * 1) +
            (GoldBadges * 100) +
            (SilverBadges * 50) +
            (BronzeBadges * 10) +
            (CommentCount * 0.5) +
            (LN(GREATEST(TotalViewsOnQuestions, 1)) * 2) +
            (AvgAnswerScore * 5)
        ) * (1.0 + (CAST(AcceptedAnswerCount AS REAL) / GREATEST(AnswerCount, 1))) AS ImpactScore,
        -- Find the most recent post for each user
        (SELECT MAX(CreationDate) FROM Posts WHERE OwnerUserId = uas.UserId) AS LastPostDate
    FROM UserActivitySummary uas
    WHERE uas.AnswerCount > 10
),
RankedUsers AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        ImpactScore,
        LastPostDate,
        QuestionCount,
        AnswerCount,
        AcceptedAnswerCount,
        CAST(AvgAnswerScore AS DECIMAL(10,2)) as AvgAnswerScore,
        TotalViewsOnQuestions,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        DENSE_RANK() OVER (ORDER BY ImpactScore DESC) AS OverallRank,
        NTILE(100) OVER (ORDER BY ImpactScore DESC) AS Percentile,
        LAG(DisplayName, 1, 'N/A') OVER (ORDER BY ImpactScore DESC) AS UserRankedHigher,
        LEAD(DisplayName, 1, 'N/A') OVER (ORDER BY ImpactScore DESC) AS UserRankedLower
    FROM UserScoreCalculation
    WHERE LastPostDate > (CURRENT_TIMESTAMP - INTERVAL '5 year')
)
SELECT
    ru.OverallRank,
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    CAST(ru.ImpactScore AS DECIMAL(18,2)) AS ImpactScore,
    ru.Percentile,
    ru.UserRankedHigher,
    ru.UserRankedLower,
    ru.LastPostDate,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.AcceptedAnswerCount,
    ru.AvgAnswerScore,
    ru.TotalViewsOnQuestions,
    (
        -- Subquery to find the most common tag for this user's questions
        SELECT TagName
        FROM (
            SELECT unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName
            FROM Posts
            WHERE OwnerUserId = ru.UserId AND PostTypeId = 1 AND Tags IS NOT NULL
        ) as UserTags
        GROUP BY TagName
        ORDER BY COUNT(*) DESC, TagName
        LIMIT 1
    ) AS MostCommonTag
FROM RankedUsers ru
JOIN Users u ON ru.UserId = u.Id
WHERE ru.OverallRank <= 100 AND u.Location LIKE '%United States%'
ORDER BY ru.OverallRank;
