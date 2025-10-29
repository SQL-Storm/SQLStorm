-- {"query": "4227.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1805} 

WITH QuestionDetails AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate AS QuestionCreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        COUNT(a.Id) AS AnswerCount,
        SUM(CASE WHEN a.IsAccepted = 1 THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
        p.FavoriteCount,
        p.ViewCount,
        p.Score AS QuestionScore,
        p.Tags,
        AVG(CAST(a.Score AS DECIMAL(10, 2))) OVER (PARTITION BY p.Id) AS AvgAnswerScore
    FROM Posts p
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.CreationDate, p.OwnerUserId, u.DisplayName, u.Reputation, p.FavoriteCount, p.ViewCount, p.Score, p.Tags
),
AnswerPerformance AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS TotalAnswers,
        SUM(CASE WHEN a.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreAnswers,
        SUM(CASE WHEN a.Score < 0 THEN 1 ELSE 0 END) AS NegativeScoreAnswers,
        AVG(CAST(a.Score AS DECIMAL(10, 2))) AS AverageAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.Score) AS MinAnswerScore,
        COUNT(c.Id) AS TotalCommentsOnAnswers,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreCommentsOnAnswers,
        AVG(CAST(c.Score AS DECIMAL(10, 2))) AS AverageCommentScoreOnAnswers
    FROM Posts a
    LEFT JOIN Comments c ON a.Id = c.PostId
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
UserActivity AS (
    SELECT
        UserId,
        COUNT(Id) AS PostCount,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN PostTypeId = 1 AND Score > 0 THEN 1 ELSE 0 END) AS PositiveQuestionCount,
        SUM(CASE WHEN PostTypeId = 2 AND Score > 0 THEN 1 ELSE 0 END) AS PositiveAnswerCount,
        COUNT(DISTINCT CASE WHEN PostTypeId = 1 THEN Id ELSE NULL END) AS DistinctQuestions,
        COUNT(DISTINCT CASE WHEN PostTypeId = 2 THEN Id ELSE NULL END) AS DistinctAnswers
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND OwnerUserId <> -1
    GROUP BY UserId
),
TagEngagement AS (
    SELECT
        TRIM(UNNEST(string_to_array(REPLACE(REPLACE(Tags, '<', ''), '>', ''), '')))) AS TagName,
        COUNT(Id) AS PostCountForTag,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCountForTag,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCountForTag,
        AVG(CAST(Score AS DECIMAL(10, 2))) AS AverageScoreForTag
    FROM Posts
    WHERE Tags IS NOT NULL AND Tags <> ''
    GROUP BY TagName
),
RecentActivity AS (
    SELECT
        PostId,
        COUNT(*) AS RecentEditCount,
        MAX(CreationDate) AS LastEditDate
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY PostId
    HAVING MAX(CreationDate) > NOW() - INTERVAL '30 days'
)
SELECT
    qd.Id AS OriginalQuestionId,
    qd.Title AS QuestionTitle,
    qd.OwnerDisplayName,
    qd.OwnerReputation,
    qd.QuestionCreationDate,
    qd.FavoriteCount,
    qd.ViewCount,
    qd.QuestionScore,
    qd.Tags,
    COALESCE(ap.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(ap.PositiveScoreAnswers, 0) AS PositiveScoreAnswers,
    COALESCE(ap.AverageAnswerScore, 0.0) AS AverageAnswerScore,
    COALESCE(ap.TotalCommentsOnAnswers, 0) AS TotalCommentsOnAnswers,
    COALESCE(qd.AvgAnswerScore, 0.0) AS AvgAnswerScoreAcrossAllAnswers,
    CASE
        WHEN qd.OwnerReputation >= 10000 THEN 'High Reputation'
        WHEN qd.OwnerReputation >= 1000 THEN 'Medium Reputation'
        ELSE 'Low Reputation'
    END AS OwnerReputationTier,
    DENSE_RANK() OVER (ORDER BY qd.ViewCount DESC) AS ViewRank,
    ROW_NUMBER() OVER (PARTITION BY qd.OwnerUserId ORDER BY qd.QuestionCreationDate DESC) AS UserQuestionSequence,
    LAG(qd.QuestionCreationDate, 1, qd.QuestionCreationDate) OVER (PARTITION BY qd.OwnerUserId ORDER BY qd.QuestionCreationDate) AS PreviousQuestionDate,
    COALESCE(ua.PostCount, 0) AS TotalPostsByUser,
    COALESCE(ua.QuestionCount, 0) AS QuestionsPostedByUser,
    COALESCE(ua.AnswerCount, 0) AS AnswersPostedByUser,
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        WHERE pl.PostId = qd.Id AND pl.LinkTypeId = 3 -- Duplicate Link
    ) AS DuplicateLinkCount,
    (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = qd.Id AND v.VoteTypeId = 2 -- Upvote
    ) AS UpvoteCount,
    (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = qd.Id AND v.VoteTypeId = 3 -- Downvote
    ) AS DownvoteCount,
    CASE
        WHEN qd.Title LIKE '%[^a-zA-Z0-9 ]%' THEN 'Contains Special Characters'
        ELSE 'Standard Characters'
    END AS TitleCharacterType,
    qd.TitleLength,
    COALESCE(te.PostCountForTag, 0) AS TagPostCount,
    COALESCE(te.AverageScoreForTag, 0.0) AS TagAverageScore,
    CASE
        WHEN ra.RecentEditCount > 0 THEN 'Edited Recently'
        ELSE 'Not Edited Recently'
    END AS RecentEditStatus,
    SUBSTRING(qd.Tags FROM 2 FOR POSITION('>' IN qd.Tags) - 2) AS FirstTag,
    CASE WHEN qd.OwnerUserId IS NULL THEN 'Community' ELSE 'User' END AS OwnerType
FROM QuestionDetails qd
LEFT JOIN AnswerPerformance ap ON qd.Id = ap.QuestionId
LEFT JOIN UserActivity ua ON qd.OwnerUserId = ua.UserId
LEFT JOIN TagEngagement te ON qd.Tags LIKE '%' || te.TagName || '%' -- Simple LIKE, can be refined
LEFT JOIN RecentActivity ra ON qd.Id = ra.PostId
WHERE
    qd.QuestionCreationDate BETWEEN '2023-01-01' AND '2023-12-31'
    AND qd.OwnerReputation > 100
    AND ap.TotalAnswers > 5
ORDER BY qd.QuestionScore DESC, qd.ViewCount DESC
LIMIT 100;
