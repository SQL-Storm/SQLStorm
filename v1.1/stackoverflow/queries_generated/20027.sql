-- {"query": "20027.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1381} 

WITH UserQuestionStats AS (
    -- Step 1: Identify users with high reputation and a minimum number of questions asked.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS QuestionsAsked
    FROM
        Users u
    JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        p.PostTypeId = 1 -- Questions
        AND u.Reputation > 1500
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
    HAVING
        COUNT(p.Id) > 10
),
RankedQuestions AS (
    -- Step 2: For these users, rank their non-closed, non-community-owned questions.
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.ViewCount,
        p.Score,
        p.FavoriteCount,
        p.AnswerCount,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC, p.Score DESC) as rn,
        LAG(p.CreationDate, 1) OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevQuestionDate
    FROM
        Posts p
    WHERE
        p.OwnerUserId IN (SELECT UserId FROM UserQuestionStats)
        AND p.PostTypeId = 1
        AND p.ClosedDate IS NULL
        AND p.CommunityOwnedDate IS NULL
),
TopUserContributions AS (
    -- Step 3: Union of top questions and top answers to create a diverse set of user activities.
    SELECT
        uqs.UserId,
        uqs.DisplayName,
        uqs.Reputation,
        'Top Question' AS ContributionType,
        rq.Id AS PostId,
        rq.Title AS PostTitle,
        rq.Score,
        rq.CreationDate,
        EXTRACT(EPOCH FROM (rq.CreationDate - rq.PrevQuestionDate)) / 86400.0 AS DaysSincePrevQuestion,
        (SELECT Name FROM Badges WHERE UserId = uqs.UserId ORDER BY Date DESC LIMIT 1) as LastBadgeName -- Correlated Subquery
    FROM
        RankedQuestions rq
    JOIN
        UserQuestionStats uqs ON rq.OwnerUserId = uqs.UserId
    WHERE
        rq.rn <= 3 -- Select top 3 questions for each user
    UNION ALL
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        'Top Answer' AS ContributionType,
        p.Id AS PostId,
        'Answer to: ' || q.Title AS PostTitle,
        p.Score,
        p.CreationDate,
        NULL AS DaysSincePrevQuestion,
        (SELECT Name FROM Badges WHERE UserId = u.Id ORDER BY Date DESC LIMIT 1) as LastBadgeName
    FROM
        Posts p
    JOIN
        Posts q ON p.ParentId = q.Id
    JOIN
        Users u ON p.OwnerUserId = u.Id
    WHERE
        p.PostTypeId = 2 -- Answers
        AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) -- Answers with above-average score
        AND u.Reputation > 1500
        AND p.Id IN (
            -- Select only the top-scoring answer for users who have at least 20 answers
            SELECT Id FROM (
                SELECT Id, ROW_NUMBER() OVER(PARTITION BY OwnerUserId ORDER BY Score DESC) as rn_ans
                FROM Posts
                WHERE PostTypeId = 2 AND OwnerUserId IS NOT NULL
            ) pa
            WHERE pa.rn_ans = 1
        ) AND u.Id IN (
            SELECT OwnerUserId FROM Posts WHERE PostTypeId = 2 GROUP BY OwnerUserId HAVING COUNT(*) >= 20
        )
)
-- Step 4: Final analysis, joining various data points and calculating a composite score.
SELECT
    tuc.DisplayName,
    tuc.Reputation,
    tuc.ContributionType,
    tuc.PostTitle,
    tuc.Score,
    tuc.CreationDate,
    p.CommentCount,
    p.Tags,
    CASE
        WHEN tuc.ContributionType = 'Top Question' THEN 'Question Quality: ' ||
            CASE
                WHEN p.AnswerCount > 0 AND p.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
                WHEN p.AnswerCount > 5 THEN 'Highly Discussed'
                ELSE 'Needs Attention'
            END
        WHEN tuc.ContributionType = 'Top Answer' AND p.Score > 50 THEN 'Highly Voted Answer'
        ELSE 'Standard Contribution'
    END AS Status,
    COALESCE(aa.OwnerDisplayName, 'N/A') AS AcceptedAnswererName,
    LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<p>', '')) AS Paragraphs, -- Simple text analysis
    (tuc.Score * 0.4) + (p.CommentCount * 0.1) + (COALESCE(p.FavoriteCount, 0) * 0.5) + (tuc.Reputation / 1000.0) AS CompositeMetric,
    tuc.DaysSincePrevQuestion,
    tuc.LastBadgeName
FROM
    TopUserContributions tuc
JOIN
    Posts p ON tuc.PostId = p.Id
LEFT OUTER JOIN
    Posts aa ON p.AcceptedAnswerId = aa.Id
WHERE
    (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<database>%')
    AND tuc.CreationDate BETWEEN '2018-01-01' AND '2023-12-31'
ORDER BY
    tuc.Reputation DESC,
    CompositeMetric DESC,
    tuc.CreationDate DESC
LIMIT 100;
