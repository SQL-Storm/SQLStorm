-- {"query": "4997.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1439} 

WITH RankedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.OwnerUserId AS QuestionOwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.AnswerCount AS QuestionAnswerCount,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.CreationDate ASC) AS rn_score,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS dr_user_questions,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_day_score,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS next_day_score,
        p.ViewCount,
        UPPER(p.Tags) AS NormalizedTags,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountForPost
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.AnswerCount, p.ViewCount, p.Tags
),
HighReputationUsers AS (
    SELECT
        Id,
        DisplayName,
        Reputation,
        UpVotes,
        DownVotes,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rn_reputation
    FROM Users
    WHERE Reputation > 100000
),
AverageAnswerScore AS (
    SELECT
        p.Id AS QuestionId,
        AVG(ans.Score) AS AvgAnswerScore
    FROM Posts p
    JOIN Posts ans ON p.Id = ans.ParentId AND ans.PostTypeId = 2
    GROUP BY p.Id
),
TagUsageStats AS (
    SELECT
        TRIM(REPLACE(REPLACE(REPLACE(t.TagName, '<', ''), '>', ''), '#', '')) AS CleanTagName,
        COUNT(DISTINCT pt.PostId) AS TotalPostsWithTag,
        SUM(CASE WHEN pt.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        AVG(p.Score) AS AvgQuestionScoreForTag,
        MAX(p.CreationDate) AS LatestQuestionDateForTag
    FROM Tags t
    LEFT JOIN Posts pt ON t.TagName = ANY(STRING_TO_ARRAY(REPLACE(REPLACE(REPLACE(pt.Tags, '<', ''), '>', ''), '#', ''), ' ')) AND pt.PostTypeId = 1
    LEFT JOIN Posts p ON pt.Id = p.Id
    WHERE t.TagName IS NOT NULL AND LENGTH(t.TagName) > 2
    GROUP BY TRIM(REPLACE(REPLACE(REPLACE(t.TagName, '<', ''), '>', ''), '#', ''))
    HAVING COUNT(DISTINCT pt.PostId) > 50
)
SELECT
    rq.QuestionId,
    rq.QuestionTitle,
    u.DisplayName AS QuestionOwnerDisplayName,
    u.Reputation AS OwnerReputation,
    rq.QuestionScore,
    rq.QuestionAnswerCount,
    aas.AvgAnswerScore,
    rq.ViewCount,
    CASE WHEN rq.QuestionScore > 0 AND rq.QuestionAnswerCount > 0 THEN CAST(rq.QuestionScore AS DECIMAL) / rq.QuestionAnswerCount ELSE 0 END AS ScorePerAnswer,
    (rq.Score - rq.prev_day_score) AS DailyScoreChange,
    (rq.Score - rq.next_day_score) AS NextDayScoreDifference,
    rq.rn_score,
    rq.dr_user_questions,
    hr.DisplayName AS TopUserDisplayName,
    hr.Reputation AS TopUserReputation,
    COALESCE(rq.CommentCountForPost, 0) AS ActualCommentCount,
    CASE
        WHEN rq.NormalizedTags LIKE '%<performance>%' THEN 'Performance Related'
        WHEN rq.NormalizedTags LIKE '%<sql>%' THEN 'SQL Related'
        ELSE 'Other'
    END AS TagCategory,
    t.CleanTagName AS PrimaryTag,
    t.TotalPostsWithTag AS TagPostCount,
    t.AvgQuestionScoreForTag AS TagAvgScore,
    CASE
        WHEN ABS(JULIANDAY(rq.QuestionCreationDate) - JULIANDAY(t.LatestQuestionDateForTag)) < 30 THEN 'Recent Tag Association'
        ELSE 'Distant Tag Association'
    END AS TagRecency,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rq.QuestionId AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = rq.QuestionId AND ph.PostHistoryTypeId IN (4, 5)) AS EditHistoryCount,
    rq.QuestionCreationDate,
    t.LatestQuestionDateForTag
FROM RankedQuestions rq
LEFT JOIN Users u ON rq.QuestionOwnerUserId = u.Id
LEFT JOIN AverageAnswerScore aas ON rq.QuestionId = aas.QuestionId
LEFT JOIN HighReputationUsers hr ON hr.rn_reputation = 1 -- Joining with the single top reputation user
LEFT JOIN TagUsageStats t ON t.CleanTagName = LOWER(SUBSTRING_INDEX(SUBSTRING_INDEX(rq.NormalizedTags, '><', 1), '<', -1)) -- Assuming first tag is primary
WHERE rq.rn_score BETWEEN 1 AND 100 -- Top 100 questions by score
UNION
SELECT
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM Users u
WHERE u.Id IS NULL;
