WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Body,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostTypeDesc,
        COALESCE(p.Title, 'No Title') AS CleanTitle,
        TRIM(BOTH '<>' FROM COALESCE(p.Tags, '')) AS CleanTags,
        CHAR_LENGTH(COALESCE(p.Body, '')) AS BodyLength,
        CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate AS DaysSinceCreation_interval,
        CAST(EXTRACT(day FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate)) AS integer) AS DaysSinceCreation,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Voted'
            WHEN p.Score > 50 THEN 'Moderately Voted'
            WHEN p.Score > 10 THEN 'Low Voted'
            ELSE 'Very Low Voted'
        END AS VoteCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        RANK() OVER (ORDER BY p.Score DESC) AS GlobalScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS GlobalViewRank,
        NTILE(4) OVER (ORDER BY p.Score DESC) AS ScoreQuartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT ps.Id) AS TotalPosts,
        SUM(ps.Score) AS TotalScore,
        AVG(ps.Score) AS AvgScore,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 1 THEN ps.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 2 THEN ps.Id END) AS AnswerCount,
        MAX(ps.CreationDate) AS LastPostDate,
        CAST(EXTRACT(day FROM (MAX(ps.CreationDate) - MIN(ps.CreationDate))) AS integer) AS ActiveDays,
        CASE 
            WHEN COUNT(DISTINCT ps.Id) > 100 THEN 'Heavy Poster'
            WHEN COUNT(DISTINCT ps.Id) > 50 THEN 'Moderate Poster'
            WHEN COUNT(DISTINCT ps.Id) > 10 THEN 'Light Poster'
            ELSE 'New Poster'
        END AS PostingLevel
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
    HAVING COUNT(DISTINCT ps.Id) >= 1
),
TopQuestions AS (
    SELECT 
        ps.Id,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.OwnerUserId,
        ps.CreationDate,
        ps.PostTypeDesc,
        ps.VoteCategory,
        ps.ScoreQuartile,
        ps.UserPostRank,
        ps.GlobalScoreRank,
        u.DisplayName AS OwnerName,
        u.Reputation AS OwnerReputation
    FROM PostStats ps
    INNER JOIN UserActivity u ON ps.OwnerUserId = u.UserId
    WHERE ps.PostTypeId = 1
      AND ps.Score > (SELECT AVG(Score) FROM PostStats WHERE PostTypeId = 1)
),
UserTagAnalysis AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        STRING_AGG(DISTINCT 
            CASE 
                WHEN ps.PostTypeId = 1 AND ps.CleanTags != '' THEN ps.CleanTags 
                ELSE NULL 
            END, ', ') AS UserTags,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 1 THEN ps.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 2 THEN ps.Id END) AS AnswerCount,
        SUM(CASE WHEN ps.PostTypeId = 1 THEN ps.Score ELSE 0 END) AS QuestionScore,
        SUM(CASE WHEN ps.PostTypeId = 2 THEN ps.Score ELSE 0 END) AS AnswerScore,
        AVG(CASE WHEN ps.PostTypeId = 1 THEN ps.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN ps.PostTypeId = 2 THEN ps.Score ELSE NULL END) AS AvgAnswerScore
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
ComplexComments AS (
    SELECT 
        c.Id,
        c.PostId,
        c.Text,
        c.Score,
        c.CreationDate,
        c.UserDisplayName,
        c.UserId,
        CASE 
            WHEN CHAR_LENGTH(c.Text) > 100 THEN 'Long Comment'
            WHEN CHAR_LENGTH(c.Text) > 50 THEN 'Medium Comment'
            WHEN CHAR_LENGTH(c.Text) > 10 THEN 'Short Comment'
            ELSE 'Very Short Comment'
        END AS CommentLengthGroup,
        CAST(EXTRACT(hour FROM (CAST('2024-10-01 12:34:56' AS timestamp) - c.CreationDate)) AS integer) AS HoursSinceComment,
        POSITION('http' IN c.Text) AS HasURL,
        POSITION('@' IN c.Text) AS HasMention,
        CASE 
            WHEN POSITION('help' IN LOWER(c.Text)) > 0 THEN 1
            WHEN POSITION('please' IN LOWER(c.Text)) > 0 THEN 1
            ELSE 0
        END AS IsRequest,
        CASE 
            WHEN POSITION('thank' IN LOWER(c.Text)) > 0 THEN 1
            ELSE 0
        END AS IsThankful,
        CASE 
            WHEN c.Score < 0 THEN 'Downvoted'
            WHEN c.Score = 0 THEN 'Neutral'
            WHEN c.Score > 5 THEN 'Highly Positive'
            ELSE 'Positive'
        END AS CommentSentiment
    FROM Comments c
    WHERE c.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 day')
),
FinalAggregate AS (
    SELECT 
        ta.UserId,
        ta.DisplayName,
        ta.Reputation,
        ta.UserTags,
        ta.QuestionCount,
        ta.AnswerCount,
        ta.QuestionScore,
        ta.AnswerScore,
        ta.AvgQuestionScore,
        ta.AvgAnswerScore,
        COALESCE(ua.TotalPosts, 0) AS TotalUserPosts,
        COALESCE(ua.TotalScore, 0) AS TotalUserScore,
        COALESCE(ua.QuestionCount, 0) AS UserQuestionCount,
        COALESCE(ua.AnswerCount, 0) AS UserAnswerCount,
        ua.LastPostDate,
        ua.ActiveDays,
        ua.PostingLevel,
        COUNT(DISTINCT tc.Id) AS RecentCommentsCount,
        SUM(tc.Score) AS CommentScoreSum,
        AVG(tc.Score) AS AvgCommentScore,
        STRING_AGG(DISTINCT tc.CommentSentiment, ', ') AS CommentSentiments,
        STRING_AGG(DISTINCT tc.CommentLengthGroup, ', ') AS CommentLengths,
        CASE 
            WHEN ta.QuestionCount > 0 AND (ta.QuestionScore + ta.AnswerScore) > 100 THEN 'Highly Active'
            WHEN ta.QuestionCount > 0 AND (ta.QuestionScore + ta.AnswerScore) > 50 THEN 'Moderately Active'
            ELSE 'Less Active'
        END AS ActivityLevel,
        CASE 
            WHEN MAX(tc.HoursSinceComment) > 24 THEN 'Old Comments'
            WHEN MAX(tc.HoursSinceComment) <= 24 THEN 'Recent Comments'
            ELSE 'No Comments'
        END AS CommentRecency,
        CASE 
            WHEN COUNT(DISTINCT tc.HasURL) > 0 THEN 1
            ELSE 0
        END AS HasURLInComments,
        CASE 
            WHEN COUNT(DISTINCT tc.IsRequest) > 0 THEN 1
            ELSE 0
        END AS HasRequests,
        ROW_NUMBER() OVER (ORDER BY (ta.QuestionScore + ta.AnswerScore) DESC) AS RankByActivity,
        PERCENT_RANK() OVER (ORDER BY ta.QuestionScore DESC) AS ScorePercentile,
        ROUND((ta.QuestionScore + ta.AnswerScore) * 1.0 / NULLIF(ua.TotalScore, 0), 2) AS ContributionPercentage
    FROM UserTagAnalysis ta
    LEFT JOIN UserActivity ua ON ta.UserId = ua.UserId
    LEFT JOIN ComplexComments tc ON ta.UserId = tc.UserId
    WHERE ta.UserId IS NOT NULL
    GROUP BY ta.UserId, ta.DisplayName, ta.Reputation, ta.UserTags, ta.QuestionCount, ta.AnswerCount, 
             ta.QuestionScore, ta.AnswerScore, ta.AvgQuestionScore, ta.AvgAnswerScore, 
             ua.TotalPosts, ua.TotalScore, ua.QuestionCount, ua.AnswerCount, ua.LastPostDate, 
             ua.ActiveDays, ua.PostingLevel
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.UserTags,
    fa.QuestionCount,
    fa.AnswerCount,
    fa.QuestionScore,
    fa.AnswerScore,
    fa.AvgQuestionScore,
    fa.AvgAnswerScore,
    fa.TotalUserPosts,
    fa.TotalUserScore,
    fa.UserQuestionCount,
    fa.UserAnswerCount,
    fa.LastPostDate,
    fa.ActiveDays,
    fa.PostingLevel,
    fa.RecentCommentsCount,
    fa.CommentScoreSum,
    fa.AvgCommentScore,
    fa.CommentSentiments,
    fa.CommentLengths,
    fa.ActivityLevel,
    fa.CommentRecency,
    fa.HasURLInComments,
    fa.HasRequests,
    fa.RankByActivity,
    fa.ScorePercentile,
    fa.ContributionPercentage,
    CASE 
        WHEN fa.Reputation > 10000 THEN 'Expert'
        WHEN fa.Reputation > 5000 THEN 'Advanced'
        WHEN fa.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS ReputationTier,
    CASE 
        WHEN fa.UserTags IS NOT NULL AND CHAR_LENGTH(fa.UserTags) > 0 THEN 
            CASE 
                WHEN CHAR_LENGTH(fa.UserTags) > 200 THEN 'Multiple Specializations'
                WHEN CHAR_LENGTH(fa.UserTags) > 100 THEN 'Several Specializations'
                ELSE 'Focused Specialization'
            END
        ELSE 'No Specializations'
    END AS TagSpecialization,
    CASE 
        WHEN fa.QuestionCount > 0 AND fa.AnswerCount > 0 THEN 
            ROUND(fa.AnswerCount * 100.0 / NULLIF(fa.QuestionCount, 0), 2)
        ELSE 0 
    END AS AnswerToQuestionRatio,
    COALESCE(ROUND(fa.TotalUserScore * 1.0 / NULLIF(fa.ActiveDays, 0), 2), 0) AS ScorePerDay,
    CASE 
        WHEN fa.Reputation > 5000 AND fa.TotalUserScore > 1000 THEN 'Highly Contributing User'
        WHEN fa.Reputation > 1000 AND fa.TotalUserScore > 500 THEN 'Good Contributor'
        ELSE 'Regular User'
    END AS UserClassification,
    (
        SELECT 
            STRING_AGG(CONCAT('(', t.Id, ': ', t.TagName, ' - ', t.Count, ')'), ', ')
        FROM Tags t
        WHERE t.TagName IN (
            SELECT TRIM(value) FROM (
                -- split comma-separated tags into rows in a dialect-agnostic way using recursive CTE
                WITH RECURSIVE split(tagstr, rest) AS (
                    SELECT TRIM(COALESCE(fa.UserTags, '')), 
                           '' 
                    WHERE COALESCE(fa.UserTags, '') <> ''
                    UNION ALL
                    SELECT
                        CASE WHEN POSITION(',' IN split.tagstr) > 0 THEN TRIM(SUBSTR(split.tagstr, 1, POSITION(',' IN split.tagstr)-1)) ELSE TRIM(split.tagstr) END,
                        CASE WHEN POSITION(',' IN split.tagstr) > 0 THEN LTRIM(SUBSTR(split.tagstr, POSITION(',' IN split.tagstr)+1)) ELSE '' END
                    FROM split
                    WHERE split.tagstr <> '' AND POSITION(',' IN split.tagstr) > 0
                )
                SELECT tagstr AS value FROM split WHERE tagstr <> ''
            )
        )
    ) AS TagDetails,
    ABS(
        ROUND(
            (SELECT AVG(Score) FROM PostStats WHERE PostTypeId = 1) - 
            (SELECT AVG(Score) FROM PostStats WHERE PostTypeId = 2),
            2
        )
    ) AS QuestionAnswerScoreDifference
FROM FinalAggregate fa
WHERE fa.Reputation >= 100
ORDER BY fa.TotalUserScore DESC, fa.Reputation DESC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY;