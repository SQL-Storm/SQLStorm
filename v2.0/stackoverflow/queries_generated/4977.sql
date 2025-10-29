-- {"query": "4977.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1682} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) as rn_post_type,
        AVG(CAST(p.Score AS FLOAT)) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) AS rolling_avg_score,
        LEAD(p.Score, 1, 0) OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS next_post_score
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
),
UserPostAggregates AS (
    SELECT
        rp.OwnerUserId,
        COUNT(DISTINCT rp.PostId) AS TotalPosts,
        SUM(rp.PostScore) AS TotalScore,
        AVG(CAST(rp.PostViewCount AS FLOAT)) AS AvgViewCount,
        COUNT(CASE WHEN rp.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN rp.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        MAX(rp.PostCreationDate) AS LastPostDate,
        SUM(rp.AnswerCount) AS TotalAnswersGiven
    FROM RankedPosts rp
    GROUP BY rp.OwnerUserId
),
RecentActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        MAX(p.LastActivityDate) AS LastActivityDate,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesReceived,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesReceived,
        MAX(CASE WHEN c.CreationDate > u.LastAccessDate THEN 1 ELSE 0 END) AS HasRecentComment
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE u.Id < 500000 -- Limit to a subset of users for performance
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TagPopularity AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT ph.PostId) AS TaggedPostCount,
        SUM(CASE WHEN ph.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsTagged,
        AVG(CAST(p.Score AS FLOAT)) AS AvgQuestionScoreForTag
    FROM Tags t
    JOIN Posts p ON p.Id = ANY(SELECT ph.PostId FROM PostHistory ph WHERE ph.PostHistoryTypeId IN (3, 6) AND ph.Text LIKE '%' || t.TagName || '%')
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT ph.PostId) > 1000
),
ComplexPostAnalysis AS (
    SELECT
        rp.PostId,
        rp.PostTypeName,
        rp.PostScore,
        rp.PostViewCount,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        DATEDIFF(day, rp.PostCreationDate, COALESCE(rp.ClosedDate, CURRENT_TIMESTAMP)) AS PostAgeInDays,
        CASE
            WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN rp.PostScore > 100 THEN 'High Score'
            WHEN rp.AnswerCount > 10 THEN 'High Answered'
            ELSE 'Standard'
        END AS PostStatusCategory,
        CASE
            WHEN rp.PostTypeName = 'Question' AND rp.rolling_avg_score IS NULL THEN 0
            WHEN rp.PostTypeName = 'Question' THEN rp.rolling_avg_score
            ELSE 0
        END AS RollingAvgQuestionScore,
        rp.next_post_score,
        CONCAT(rp.PostTypeName, '-', rp.PostScore, '-', rp.CommentCount) AS CombinedInfo
    FROM RankedPosts rp
    WHERE rp.rn_post_type <= 500 -- Top 500 posts of each type
)
SELECT
    ra.DisplayName,
    ra.Reputation,
    ra.UserCreationDate,
    ra.LastActivityDate,
    upa.TotalPosts,
    upa.TotalScore,
    upa.AvgViewCount,
    upa.QuestionCount,
    upa.AnswerCount AS TotalAnswersContributed,
    upa.TotalAnswersGiven,
    ra.UpVotesReceived,
    ra.DownVotesReceived,
    COALESCE(ra.HasRecentComment, 0) AS HasRecentComment,
    COUNT(DISTINCT cpa.PostId) AS AnalyzedPostsCount,
    SUM(CASE WHEN cpa.PostStatusCategory = 'High Score' THEN 1 ELSE 0 END) AS HighScorePostCount,
    AVG(CAST(cpa.PostAgeInDays AS FLOAT)) AS AvgPostAgeOfAnalyzedPosts,
    MAX(cpa.RollingAvgQuestionScore) AS MaxRollingAvgQuestionScore,
    MIN(cpa.CombinedInfo) AS MinCombinedInfo,
    COUNT(tp.TagName) AS FavoriteTagCount,
    SUM(tp.TaggedPostCount) AS TotalTaggedPostCountForFavTags,
    AVG(tp.AvgQuestionScoreForTag) AS AvgQuestionScoreForFavTags
FROM RecentActivity ra
JOIN UserPostAggregates upa ON ra.UserId = upa.OwnerUserId
LEFT JOIN ComplexPostAnalysis cpa ON ra.UserId = cpa.OwnerUserId
LEFT JOIN (
    SELECT DISTINCT
        rp.OwnerUserId,
        tp.TagName
    FROM RankedPosts rp
    JOIN PostHistory ph ON rp.PostId = ph.PostId AND ph.PostHistoryTypeId IN (3, 6)
    JOIN Tags tp ON ph.Text LIKE '%' || tp.TagName || '%'
    WHERE rp.PostTypeId = 1 AND rp.PostScore > 50 -- Focus on highly scored questions
    ORDER BY NEWID() -- Randomly select some tags per user
    LIMIT 5
) AS UserFavoriteTags ON ra.UserId = UserFavoriteTags.OwnerUserId
LEFT JOIN TagPopularity tp ON UserFavoriteTags.TagName = tp.TagName
GROUP BY
    ra.DisplayName,
    ra.Reputation,
    ra.UserCreationDate,
    ra.LastActivityDate,
    upa.TotalPosts,
    upa.TotalScore,
    upa.AvgViewCount,
    upa.QuestionCount,
    upa.AnswerCount,
    upa.TotalAnswersGiven,
    ra.UpVotesReceived,
    ra.DownVotesReceived,
    ra.HasRecentComment
HAVING COUNT(DISTINCT cpa.PostId) > 5 -- Users with at least 5 analyzed posts
ORDER BY ra.Reputation DESC, upa.TotalScore DESC;