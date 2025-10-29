-- {"query": "7080.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2562} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as TotalAnswers,
        COUNT(DISTINCT c.Id) as TotalComments,
        COUNT(DISTINCT b.Id) as TotalBadges,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        DENSE_RANK() OVER (ORDER BY u.Views DESC) as ViewRank,
        NTILE(10) OVER (ORDER BY u.Reputation DESC) as ReputationDecile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostPerformance AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.PostTypeId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostTypeDesc,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) as DaysSinceCreation,
        CASE 
            WHEN p.Score >= 100 THEN 'High'
            WHEN p.Score >= 50 THEN 'Medium'
            ELSE 'Low'
        END as ScoreCategory,
        COALESCE(p.Tags, '') as TagsList,
        STRING_AGG(
            SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2), 
            ', ' 
        ) as TagArray,
        CASE 
            WHEN p.Score > 0 AND p.ViewCount > 0 
            THEN CAST(p.Score AS FLOAT) / CAST(p.ViewCount AS FLOAT) 
            ELSE 0 
        END as ScoreToViewRatio,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRankByType,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRankByPost,
        PERCENT_RANK() OVER (ORDER BY p.Score) as ScorePercentile,
        NTH_VALUE(p.Title, 1) OVER (
            ORDER BY p.Score DESC 
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) as HighestScoringPostTitle,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PreviousPostScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
CommentActivity AS (
    SELECT 
        c.PostId,
        c.UserId,
        c.Score,
        c.Text,
        c.CreationDate,
        c.UserDisplayName,
        DATEDIFF(second, c.CreationDate, GETDATE()) as SecondsSinceComment,
        CASE 
            WHEN c.Score > 10 THEN 'HighlyVoted'
            WHEN c.Score > 0 THEN 'Positive'
            ELSE 'Neutral'
        END as CommentSentiment,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate ASC) as CommentSequence,
        COUNT(*) OVER (PARTITION BY c.PostId) as TotalCommentsPerPost
    FROM Comments c
),
DetailedUserAnalysis AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPosts,
        uas.TotalQuestions,
        uas.TotalAnswers,
        uas.TotalComments,
        uas.TotalBadges,
        uas.ReputationRank,
        uas.ViewRank,
        uas.ReputationDecile,
        CASE 
            WHEN uas.TotalQuestions > 0 THEN CAST(uas.TotalAnswers AS FLOAT) / CAST(uas.TotalQuestions AS FLOAT)
            ELSE 0 
        END as AnswerToQuestionRatio,
        CASE 
            WHEN (uas.UpVotes + uas.DownVotes) > 0 THEN 
                CAST(uas.UpVotes AS FLOAT) / CAST((uas.UpVotes + uas.DownVotes) AS FLOAT)
            ELSE 0 
        END as UpvoteRatio,
        CASE 
            WHEN uas.TotalBadges > 0 THEN uas.TotalBadges 
            ELSE 0 
        END as BadgeScore,
        CASE 
            WHEN uas.Reputation > 10000 THEN 'Expert'
            WHEN uas.Reputation > 1000 THEN 'Intermediate'
            WHEN uas.Reputation > 100 THEN 'Beginner'
            ELSE 'Newbie'
        END as UserLevel,
        'Top ' + CAST(uas.ReputationRank AS VARCHAR) + ' of ' + CAST(COUNT(*) OVER() AS VARCHAR) as RankDescription
    FROM UserActivityStats uas
),
PostAnalysis AS (
    SELECT
        pp.PostId,
        pp.Title,
        pp.Score,
        pp.ViewCount,
        pp.AnswerCount,
        pp.CommentCount,
        pp.FavoriteCount,
        pp.ScoreToViewRatio,
        pp.ScoreCategory,
        pp.PostTypeDesc,
        pp.DaysSinceCreation,
        pp.ScoreRankByType,
        pp.ViewRankByPost,
        pp.ScorePercentile,
        pp.HighestScoringPostTitle,
        pp.PreviousPostScore,
        COALESCE(
            CASE 
                WHEN pp.TagsList LIKE '%<%' AND pp.TagsList LIKE '%>%' 
                THEN (SELECT COUNT(*) FROM STRING_SPLIT(SUBSTRING(pp.TagsList, 2, LEN(pp.TagsList) - 2), '><'))
                ELSE 0
            END,
            0
        ) as TagCount,
        CASE 
            WHEN pp.Score > 0 AND pp.ViewCount > 0 AND pp.AnswerCount > 0 
            THEN CAST(pp.Score AS FLOAT) / CAST((pp.ViewCount + pp.AnswerCount) AS FLOAT)
            ELSE 0 
        END as WeightedScore,
        CASE 
            WHEN pp.CreationDate >= DATEADD(day, -30, GETDATE()) THEN 'Recent'
            WHEN pp.CreationDate >= DATEADD(day, -90, GETDATE()) THEN 'Medium'
            ELSE 'Old'
        END as PostAgeCategory
    FROM PostPerformance pp
),
CombinedAnalysis AS (
    SELECT 
        dua.UserId,
        dua.DisplayName,
        dua.Reputation,
        dua.TotalPosts,
        dua.TotalQuestions,
        dua.TotalAnswers,
        dua.TotalComments,
        dua.TotalBadges,
        dua.ReputationRank,
        dua.ViewRank,
        dua.ReputationDecile,
        dua.AnswerToQuestionRatio,
        dua.UpvoteRatio,
        dua.BadgeScore,
        dua.UserLevel,
        dua.RankDescription,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.ScoreToViewRatio,
        pa.ScoreCategory,
        pa.PostTypeDesc,
        pa.DaysSinceCreation,
        pa.ScoreRankByType,
        pa.ViewRankByPost,
        pa.ScorePercentile,
        pa.HighestScoringPostTitle,
        pa.PreviousPostScore,
        pa.TagCount,
        pa.WeightedScore,
        pa.PostAgeCategory
    FROM DetailedUserAnalysis dua
    LEFT JOIN PostAnalysis pa ON dua.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = pa.PostId)
    WHERE dua.UserId IN (
        SELECT DISTINCT OwnerUserId FROM Posts WHERE PostTypeId = 1
        UNION
        SELECT DISTINCT OwnerUserId FROM Posts WHERE PostTypeId = 2
    )
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.TotalPosts,
    ca.TotalQuestions,
    ca.TotalAnswers,
    ca.TotalComments,
    ca.TotalBadges,
    ca.ReputationRank,
    ca.ViewRank,
    ca.ReputationDecile,
    ca.AnswerToQuestionRatio,
    ca.UpvoteRatio,
    ca.BadgeScore,
    ca.UserLevel,
    ca.RankDescription,
    ca.PostId,
    ca.Title,
    ca.Score,
    ca.ViewCount,
    ca.AnswerCount,
    ca.CommentCount,
    ca.FavoriteCount,
    ca.ScoreToViewRatio,
    ca.ScoreCategory,
    ca.PostTypeDesc,
    ca.DaysSinceCreation,
    ca.ScoreRankByType,
    ca.ViewRankByPost,
    ca.ScorePercentile,
    ca.HighestScoringPostTitle,
    ca.PreviousPostScore,
    ca.TagCount,
    ca.WeightedScore,
    ca.PostAgeCategory,
    CASE 
        WHEN ca.Reputation > 10000 THEN 'Excellent'
        WHEN ca.Reputation > 5000 AND ca.Score > 50 THEN 'Very Good'
        WHEN ca.Reputation > 1000 OR ca.Score > 100 THEN 'Good'
        ELSE 'Average'
    END as PerformanceLevel,
    CASE 
        WHEN ca.TotalQuestions > 0 AND ca.TotalAnswers > 0 AND ca.AnswerToQuestionRatio > 1 THEN 'High Engagement'
        WHEN ca.TotalComments > 0 AND ca.Score > 30 THEN 'Active'
        ELSE 'Passive'
    END as EngagementLevel,
    COUNT(*) OVER() as TotalRecords,
    MAX(ca.Reputation) OVER() as MaxReputation,
    AVG(ca.Score) OVER() as AvgScore,
    MIN(ca.ViewCount) OVER() as MinViewCount,
    ROW_NUMBER() OVER (ORDER BY ca.Reputation DESC, ca.Score DESC, ca.ViewCount DESC) as RowNumber
FROM CombinedAnalysis ca
WHERE 
    ca.Reputation > (
        SELECT AVG(Reputation) FROM Users 
        WHERE Id IN (SELECT DISTINCT OwnerUserId FROM Posts WHERE PostTypeId IN (1, 2))
    )
    AND 
    (
        ca.PostAgeCategory IS NULL 
        OR ca.PostAgeCategory IN ('Recent', 'Medium')
    )
    AND 
    (
        ca.ScoreCategory IS NULL 
        OR ca.ScoreCategory IN ('High', 'Medium')
    )
    AND 
    (
        ca.UserLevel IS NULL 
        OR ca.UserLevel IN ('Expert', 'Intermediate')
    )
    AND 
    (
        EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = ca.UserId AND b.Class = 1)
        OR EXISTS (SELECT 1 FROM Votes v WHERE v.UserId = ca.UserId AND v.VoteTypeId = 2)
        OR EXISTS (SELECT 1 FROM Comments c WHERE c.UserId = ca.UserId)
        OR EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.PostTypeId = 1)
        OR EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.PostTypeId = 2)
    )
    AND 
    ca.Score BETWEEN (
        SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY p.Score) FROM Posts p
    ) AND (
        SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY p.Score) FROM Posts p
    )
    AND 
    ca.ViewCount >= (
        SELECT AVG(ViewCount) FROM Posts 
        WHERE PostTypeId IN (1, 2) AND ViewCount IS NOT NULL
    )
    AND 
    (
        ca.TagCount > 0 
        OR ca.Score > 100 
        OR ca.ViewCount > 1000
    )
ORDER BY 
    ca.Reputation DESC,
    ca.Score DESC,
    ca.ViewCount DESC,
    ca.LastPostDate DESC,
    ca.LastCommentDate DESC
OFFSET 100 ROWS 
FETCH NEXT 500 ROWS ONLY;