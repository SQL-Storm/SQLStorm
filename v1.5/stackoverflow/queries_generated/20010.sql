-- {"query": "20010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1616} 

WITH UserPostStats AS (
    -- CTE 1: Aggregate post statistics for users with high reputation.
    -- This identifies active, influential users who ask questions.
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.OwnerUserId IS NOT NULL
        AND u.Reputation > 15000 -- Filter for high-reputation users
        AND u.CreationDate < (CURRENT_TIMESTAMP - INTERVAL '5 year') -- Filter for established users
    GROUP BY p.OwnerUserId
    HAVING 
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) >= 10 -- Must have asked at least 10 questions
        AND COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) > 0 -- Must have provided at least one answer
),
RankedQuestions AS (
    -- CTE 2: For each qualifying user, find their most recent question that has answers.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.CreationDate,
        p.Tags,
        p.FavoriteCount,
        p.ViewCount,
        p.AnswerCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE 
        p.PostTypeId = 1 -- Questions only
        AND p.AnswerCount > 0 -- Must have answers to be interesting
        AND p.OwnerUserId IN (SELECT UserId FROM UserPostStats)
),
TopRankedAnswers AS (
    -- CTE 3: For all questions, rank their answers by score. We will later join this with the selected questions.
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.OwnerUserId AS AnswererUserId,
        p.Score AS AnswerScore,
        p.Body AS AnswerBody,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) as rn
    FROM Posts p
    WHERE 
        p.PostTypeId = 2 -- Answers only
        AND p.OwnerUserId IS NOT NULL
),
UserBadgeDetails AS (
    -- CTE 4: Consolidate badge information for users, counting different classes of badges.
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
)
-- Final SELECT: Combine all the above information to generate a comprehensive report.
-- The report shows top users, their latest significant question, and the top 3 answers for that question.
SELECT
    DENSE_RANK() OVER (ORDER BY ups.AvgQuestionScore DESC, u.Reputation DESC) AS UserRank,
    u.DisplayName AS QuestionerName,
    u.Reputation AS QuestionerReputation,
    CAST(ups.QuestionCount AS numeric) / ups.AnswerCount AS QuestionToAnswerRatio,
    EXTRACT(DAY FROM (ups.LastPostDate - ups.FirstPostDate)) AS UserActivitySpanDays,
    q.Title AS LatestQuestionTitle,
    q.Score AS QuestionScore,
    q.CreationDate AS QuestionDate,
    REPLACE(REPLACE(q.Tags, '<', '['), '>', ']') AS FormattedTags,
    -- Correlated subquery to get the number of comments on the question
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.PostId) AS QuestionCommentCount,
    -- Correlated subquery to calculate the time from question to first answer
    (SELECT MIN(a_sub.CreationDate) - q.CreationDate FROM Posts a_sub WHERE a_sub.ParentId = q.PostId) AS TimeToFirstAnswer,
    COALESCE(ans_user.DisplayName, 'N/A') AS AnswererName,
    COALESCE(ans_user.Reputation, 0) AS AnswererReputation,
    COALESCE(ans_badges.GoldBadges, 0) AS AnswererGoldBadges,
    tra.AnswerScore,
    -- Complex CASE expression to categorize answer quality relative to the question
    CASE
        WHEN tra.AnswerScore > q.Score * 2 THEN 'Exceptional Answer'
        WHEN tra.AnswerScore > q.Score THEN 'High-Quality Answer'
        WHEN tra.AnswerScore > 0 THEN 'Good Answer'
        ELSE 'Neutral or Downvoted Answer'
    END AS AnswerQualityCategory,
    LENGTH(tra.AnswerBody) AS AnswerLength,
    SUBSTRING(tra.AnswerBody, 1, 120) || '...' AS AnswerSnippet
FROM 
    UserPostStats ups
JOIN 
    Users u ON ups.UserId = u.Id
JOIN 
    RankedQuestions q ON ups.UserId = q.OwnerUserId AND q.rn = 1
-- Use LEFT JOIN to include questions even if they don't have answers that meet our subquery's criteria (unlikely due to AnswerCount > 0 filter, but good practice)
LEFT JOIN 
    TopRankedAnswers tra ON q.PostId = tra.QuestionId AND tra.rn <= 3
LEFT JOIN 
    Users ans_user ON tra.AnswererUserId = ans_user.Id
LEFT JOIN 
    UserBadgeDetails ans_badges ON tra.AnswererUserId = ans_badges.UserId
-- Complex predicate combining multiple conditions
WHERE 
    (q.FavoriteCount > (SELECT AVG(FavoriteCount) FROM Posts WHERE PostTypeId = 1 AND FavoriteCount IS NOT NULL) OR q.ViewCount > 10000)
    AND q.ClosedDate IS NULL
    AND u.DisplayName NOT LIKE 'user%'
    -- Correlated EXISTS to check if the question has ever been closed and then reopened
    AND EXISTS (
        SELECT 1
        FROM PostHistory ph_close
        WHERE ph_close.PostId = q.PostId AND ph_close.PostHistoryTypeId = 10 -- Post Closed
    )
    AND EXISTS (
        SELECT 1
        FROM PostHistory ph_reopen
        WHERE ph_reopen.PostId = q.PostId AND ph_reopen.PostHistoryTypeId = 11 -- Post Reopened
    )
ORDER BY
    UserRank,
    QuestionerName,
    tra.rn;

