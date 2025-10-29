-- {"query": "7987.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3266} 
WITH UserActivitySummary AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT v.Id) as VoteCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        MAX(b.Date) as LastBadgeDate,
        AVG(p.Score) as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags,
        CASE 
            WHEN COUNT(DISTINCT p.Id) = 0 THEN 'Inactive'
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Active'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Moderately Active'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Somewhat Active'
            ELSE 'New User'
        END as ActivityLevel,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Expert'
            WHEN u.Reputation > 5000 THEN 'Advanced'
            WHEN u.Reputation > 1000 THEN 'Intermediate'
            WHEN u.Reputation > 100 THEN 'Beginner'
            ELSE 'Newbie'
        END as ReputationLevel,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1) as QuestionCount,
        (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = u.Id AND p3.PostTypeId = 2) as AnswerCount,
        (SELECT COUNT(*) FROM Posts p4 WHERE p4.OwnerUserId = u.Id AND p4.PostTypeId = 3) as WikiCount,
        (SELECT COUNT(*) FROM Posts p5 WHERE p5.OwnerUserId = u.Id AND p5.PostTypeId IN (4,5)) as TagWikiCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ParentId,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as RankByScore,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as RankByViews,
        NTILE(10) OVER (ORDER BY p.CreationDate) as CreationQuartile,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgUserScore,
        CASE 
            WHEN p.AnswerCount > 0 THEN 'Has Answers'
            WHEN p.PostTypeId = 1 THEN 'Question No Answers'
            ELSE 'Other Post'
        END as PostCategory
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) AND p.Score > 0
),
UserPostStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as NumPosts,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        MAX(p.Score) as MaxScore,
        MIN(p.Score) as MinScore,
        STDEV(p.Score) as ScoreStdDev,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) as WikiCount,
        STRING_AGG(DISTINCT p.PostTypeId::VARCHAR, ', ') as PostTypesUsed,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Title END, ' | ') as QuestionTitles
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= '2020-01-01'
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 0
),
ComplexPostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.OwnerUserId,
        p.CreationDate,
        CASE 
            WHEN LENGTH(p.Body) > 1000 THEN 'Long Body'
            WHEN LENGTH(p.Body) > 500 THEN 'Medium Body'
            WHEN LENGTH(p.Body) > 100 THEN 'Short Body'
            ELSE 'Very Short Body'
        END as BodyLengthCategory,
        CASE 
            WHEN POSITION('code' IN LOWER(p.Body)) > 0 THEN 'Has Code'
            WHEN POSITION('javascript' IN LOWER(p.Body)) > 0 THEN 'JavaScript Content'
            WHEN POSITION('python' IN LOWER(p.Body)) > 0 THEN 'Python Content'
            WHEN POSITION('sql' IN LOWER(p.Body)) > 0 THEN 'SQL Content'
            WHEN POSITION('html' IN LOWER(p.Body)) > 0 THEN 'HTML Content'
            WHEN POSITION('css' IN LOWER(p.Body)) > 0 THEN 'CSS Content'
            ELSE 'Generic Content'
        END as ContentCategory,
        CASE 
            WHEN p.Score >= 100 THEN 'Highly Rated'
            WHEN p.Score >= 50 THEN 'Moderately Rated'
            WHEN p.Score >= 10 THEN 'Low Rated'
            ELSE 'Very Low Rated'
        END as RatingCategory,
        ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as ScoreRankPerUser,
        DENSE_RANK() OVER (ORDER BY p.CreationDate) as CreationRank,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) as NextScore,
        NTH_VALUE(p.Score, 5) OVER (ORDER BY p.Score DESC) as FifthHighestScore,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = p.OwnerUserId AND p2.CreationDate > p.CreationDate) as PostsAfterThis,
        (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = p.OwnerUserId AND p3.CreationDate < p.CreationDate) as PostsBeforeThis,
        COALESCE(p.AnswerCount, 0) * 1.0 / NULLIF(p.ViewCount, 0) as AnswerToViewRatio,
        COALESCE(p.CommentCount, 0) * 1.0 / NULLIF(p.ViewCount, 0) as CommentToViewRatio,
        (p.Score + COALESCE(p.ViewCount, 0) + COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0)) as CompositeScore
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) AND p.CreationDate > '2021-01-01'
),
PostTagAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Tags,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><') as TagArray,
        ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1) as TagCount,
        CASE 
            WHEN ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1) > 5 THEN 'Tag Heavy'
            WHEN ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1) > 3 THEN 'Tag Moderate'
            WHEN ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1) > 1 THEN 'Tag Light'
            ELSE 'No Tags'
        END as TagIntensity,
        ARRAY_POSITION(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 'java') as JavaTagPosition,
        ARRAY_POSITION(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 'python') as PythonTagPosition,
        ARRAY_POSITION(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 'javascript') as JavaScriptTagPosition,
        ARRAY_POSITION(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 'c++') as CppTagPosition,
        ARRAY_POSITION(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 'sql') as SqlTagPosition
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1
),
FinalComplexAnalysis AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.Views,
        uas.UpVotes,
        uas.DownVotes,
        uas.PostCount,
        uas.CommentCount,
        uas.BadgeCount,
        uas.VoteCount,
        uas.LastPostDate,
        uas.LastCommentDate,
        uas.LastBadgeDate,
        uas.AvgPostScore,
        uas.ActivityLevel,
        uas.ReputationLevel,
        ups.NumPosts,
        ups.TotalScore,
        ups.AvgScore,
        ups.MaxScore,
        ups.MinScore,
        ups.ScoreStdDev,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.WikiCount,
        ups.PostTypesUsed,
        ups.QuestionTitles,
        CASE 
            WHEN ups.AvgScore > 10 AND ups.QuestionCount > 5 THEN 'High Performing User'
            WHEN ups.AvgScore > 5 AND ups.QuestionCount > 2 THEN 'Moderately Performing User'
            WHEN ups.AvgScore > 0 AND ups.QuestionCount > 0 THEN 'Beginner User'
            ELSE 'Inactive User'
        END as UserPerformanceLevel
    FROM UserActivitySummary uas
    INNER JOIN UserPostStats ups ON uas.UserId = ups.UserId
    WHERE uas.PostCount > 0 AND ups.NumPosts > 0
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.Views,
    fa.UpVotes,
    fa.DownVotes,
    fa.PostCount,
    fa.CommentCount,
    fa.BadgeCount,
    fa.VoteCount,
    fa.LastPostDate,
    fa.LastCommentDate,
    fa.LastBadgeDate,
    fa.AvgPostScore,
    fa.ActivityLevel,
    fa.ReputationLevel,
    fa.NumPosts,
    fa.TotalScore,
    fa.AvgScore,
    fa.MaxScore,
    fa.MinScore,
    fa.ScoreStdDev,
    fa.QuestionCount,
    fa.AnswerCount,
    fa.WikiCount,
    fa.PostTypesUsed,
    fa.QuestionTitles,
    fa.UserPerformanceLevel,
    CASE 
        WHEN fa.QuestionCount > 0 AND fa.AnswerCount > 0 
        THEN 100.0 * fa.AnswerCount / NULLIF(fa.QuestionCount, 0)
        ELSE NULL 
    END as AnswerPerQuestionRatio,
    CASE 
        WHEN fa.BadgeCount > 0 
        THEN (fa.Reputation * 1.0 / NULLIF(fa.BadgeCount, 0))
        ELSE NULL 
    END as ReputationPerBadge,
    COUNT(*) OVER() as TotalSelectedUsers,
    ROW_NUMBER() OVER (ORDER BY fa.Reputation DESC) as ReputationRank,
    DENSE_RANK() OVER (ORDER BY fa.PostCount DESC) as PostCountRank,
    NTH_VALUE(fa.Reputation, 1) OVER (ORDER BY fa.Reputation DESC) as TopReputation,
    FIRST_VALUE(fa.DisplayName) OVER (ORDER BY fa.Reputation DESC) as TopReputationUser,
    LAG(fa.Reputation, 1, 0) OVER (ORDER BY fa.Reputation DESC) as PreviousReputation,
    LEAD(fa.Reputation, 1, 0) OVER (ORDER BY fa.Reputation DESC) as NextReputation,
    AVG(fa.Reputation) OVER() as AvgReputation,
    VARIANCE(fa.Reputation) OVER() as ReputationVariance,
    COUNT(*) OVER (PARTITION BY fa.ActivityLevel) as UsersByActivityLevel,
    RANK() OVER (PARTITION BY fa.ReputationLevel ORDER BY fa.Reputation DESC) as ReputationLevelRank,
    CASE 
        WHEN fa.UserPerformanceLevel IN ('High Performing User', 'Moderately Performing User') 
        THEN 'Engaged User'
        ELSE 'Non-Engaged User' 
    END as EngagementLevel,
    CASE 
        WHEN fa.Reputation > 50000 AND fa.BadgeCount > 100 THEN 'Elite Contributor'
        WHEN fa.Reputation > 10000 AND fa.BadgeCount > 50 THEN 'Experienced Contributor'
        WHEN fa.Reputation > 1000 AND fa.BadgeCount > 10 THEN 'Contributor'
        WHEN fa.Reputation > 100 THEN 'Beginner Contributor'
        ELSE 'New Contributor'
    END as ContributorTier,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.OwnerUserId = fa.UserId 
        AND p.CreationDate >= '2021-01-01' 
        AND p.PostTypeId = 1
    ) as RecentQuestionCount,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.OwnerUserId = fa.UserId 
        AND p.CreationDate >= '2021-01-01' 
        AND p.PostTypeId = 2
    ) as RecentAnswerCount,
    (
        SELECT AVG(p.Score) 
        FROM Posts p 
        WHERE p.OwnerUserId = fa.UserId 
        AND p.CreationDate >= '2021-01-01'
    ) as RecentAvgScore
FROM FinalComplexAnalysis fa
WHERE fa.Reputation > 100
  AND (fa.UserPerformanceLevel IN ('High Performing User', 'Moderately Performing User'))
  AND fa.ActivityLevel IN ('Active', 'Moderately Active')
ORDER BY fa.Reputation DESC, fa.PostCount DESC, fa.TotalScore DESC
LIMIT 5000;