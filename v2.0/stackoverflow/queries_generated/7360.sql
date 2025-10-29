-- {"query": "7360.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2255} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2,3) THEN v.Id END) as VoteCount,
        MAX(p.CreationDate) as LastPostDate,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
        RANK() OVER (ORDER BY u.Reputation DESC) as RepRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) DESC) as QuestionRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.CreationDate >= '2010-01-01' 
      AND u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
TopUsers AS (
    SELECT UserId, DisplayName, Reputation, TotalPosts, Questions, Answers, Comments, Badges, VoteCount
    FROM UserActivityStats
    WHERE PostRank <= 50 AND RepRank <= 50
),
PostComplexity AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        CASE WHEN p.AnswerCount > 0 THEN 'HasAnswers' ELSE 'NoAnswers' END as AnswerStatus,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 0 THEN 'LowVoted'
            ELSE 'Unvoted'
        END as VoteCategory,
        LENGTH(p.Body) as BodyLength,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        COALESCE(p.CommentCount, 0) as CommentCount,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        DATEDIFF(p.CreationDate, '2010-01-01') as DaysSince2010,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        PERCENT_RANK() OVER (ORDER BY p.Score) as ScorePercentile,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgUserScore,
        CASE 
            WHEN p.ParentId IS NOT NULL THEN (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id)
            ELSE 0
        END as NestedReplies
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) AND p.CreationDate >= '2010-01-01'
),
PostTagAnalysis AS (
    SELECT 
        pc.PostId,
        pc.Title,
        pc.Score,
        pc.ViewCount,
        pc.CreationDate,
        pc.OwnerUserId,
        COALESCE(REGEXP_REPLACE(REGEXP_REPLACE(pc.Tags, '<', ''), '>', ''), '') as CleanTags,
        STRING_TO_ARRAY(COALESCE(REGEXP_REPLACE(REGEXP_REPLACE(pc.Tags, '<', ''), '>', ''), ''), '>') as TagArray,
        CASE 
            WHEN pc.Tags LIKE '%<%' AND pc.Tags LIKE '%>%' THEN 
                (SELECT COUNT(*) FROM UNNEST(STRING_TO_ARRAY(COALESCE(REGEXP_REPLACE(REGEXP_REPLACE(pc.Tags, '<', ''), '>', ''), ''), '>'))) 
            ELSE 0 
        END as TagCount,
        (SELECT COUNT(*) FROM Posts WHERE ParentId = pc.PostId AND PostTypeId = 2) as AnswerCount,
        (SELECT STRING_AGG(UserId::VARCHAR, ',') FROM Votes v WHERE v.PostId = pc.PostId AND v.VoteTypeId = 2) as UpVoterIds,
        (SELECT STRING_AGG(UserId::VARCHAR, ',') FROM Votes v WHERE v.PostId = pc.PostId AND v.VoteTypeId = 3) as DownVoterIds
    FROM PostComplexity pc
),
EngagementMetrics AS (
    SELECT 
        pca.PostId,
        pca.Title,
        pca.Score,
        pca.ViewCount,
        pca.CreationDate,
        pca.OwnerUserId,
        pca.CleanTags,
        pca.TagCount,
        pca.AnswerCount,
        pca.UpVoterIds,
        pca.DownVoterIds,
        CASE 
            WHEN pca.TagCount > 5 THEN 'HighTagDensity'
            WHEN pca.TagCount > 3 THEN 'MediumTagDensity'
            ELSE 'LowTagDensity' 
        END as TagDensity,
        CASE 
            WHEN pca.AnswerCount > 0 AND pca.AnswerCount < 3 THEN 'FewAnswers'
            WHEN pca.AnswerCount >= 3 AND pca.AnswerCount < 10 THEN 'ModerateAnswers'
            WHEN pca.AnswerCount >= 10 THEN 'ManyAnswers'
            ELSE 'NoAnswers' 
        END as AnswerDensity,
        (CASE WHEN pca.TagCount > 0 THEN (pca.AnswerCount::FLOAT / pca.TagCount) ELSE 0 END) as AnswersPerTag,
        ROW_NUMBER() OVER (ORDER BY pca.Score DESC) as OverallScoreRank,
        RANK() OVER (PARTITION BY pca.OwnerUserId ORDER BY pca.Score DESC) as UserScoreRank
    FROM PostTagAnalysis pca
),
FinalResult AS (
    SELECT 
        em.PostId,
        em.Title,
        em.Score,
        em.ViewCount,
        em.CreationDate,
        em.OwnerUserId,
        em.CleanTags,
        em.TagCount,
        em.AnswerCount,
        em.TagDensity,
        em.AnswerDensity,
        em.AnswersPerTag,
        em.OverallScoreRank,
        em.UserScoreRank,
        tu.DisplayName,
        tu.Reputation,
        tu.TotalPosts,
        tu.Questions,
        tu.Answers,
        tu.Comments,
        tu.Badges,
        tu.VoteCount,
        tu.PostRank,
        tu.RepRank,
        tu.QuestionRank,
        CASE 
            WHEN em.OverallScoreRank <= 100 THEN 'TopScoring'
            WHEN em.OverallScoreRank <= 500 THEN 'HighScoring'
            WHEN em.OverallScoreRank <= 1000 THEN 'MediumScoring'
            ELSE 'LowScoring'
        END as ScoreTier,
        CASE 
            WHEN em.AnswersPerTag >= 2 THEN 'HighEngagement'
            WHEN em.AnswersPerTag >= 1 THEN 'ModerateEngagement'
            ELSE 'LowEngagement'
        END as EngagementLevel,
        COALESCE(
            CASE 
                WHEN em.AnswersPerTag >= 2 THEN 'High'
                WHEN em.AnswersPerTag >= 1 THEN 'Medium' 
                ELSE 'Low'
            END, 
            'None'
        ) as ResponseQuality,
        CONCAT(
            'Post: ', em.Title, 
            ' | Tags: ', em.CleanTags, 
            ' | Owner: ', COALESCE(tu.DisplayName, 'Unknown'),
            ' | Score: ', em.Score,
            ' | Views: ', em.ViewCount,
            ' | Answers: ', em.AnswerCount,
            ' | Tags: ', em.TagCount
        ) as DetailedSummary
    FROM EngagementMetrics em
    INNER JOIN TopUsers tu ON em.OwnerUserId = tu.UserId
    WHERE em.CreationDate >= '2010-01-01' 
      AND em.CreationDate <= '2022-12-31'
      AND em.Score > 0
      AND em.ViewCount > 0
)
SELECT 
    PostId,
    Title,
    Score,
    ViewCount,
    CreationDate,
    OwnerUserId,
    CleanTags,
    TagCount,
    AnswerCount,
    TagDensity,
    AnswerDensity,
    AnswersPerTag,
    OverallScoreRank,
    UserScoreRank,
    DisplayName,
    Reputation,
    TotalPosts,
    Questions,
    Answers,
    Comments,
    Badges,
    VoteCount,
    PostRank,
    RepRank,
    QuestionRank,
    ScoreTier,
    EngagementLevel,
    ResponseQuality,
    DetailedSummary,
    COUNT(*) OVER() as TotalResults,
    AVG(Score) OVER() as AvgScore,
    MAX(ViewCount) OVER() as MaxViews,
    MIN(CreationDate) OVER() as EarliestPostDate,
    MAX(CreationDate) OVER() as LatestPostDate,
    RANK() OVER (ORDER BY Score DESC) as GlobalScoreRank,
    DENSE_RANK() OVER (ORDER BY ViewCount DESC) as GlobalViewRank,
    NTILE(4) OVER (ORDER BY Score DESC) as Quartile,
    LAG(Title, 1) OVER (ORDER BY OverallScoreRank) as PreviousTitle,
    LEAD(Title, 1) OVER (ORDER BY OverallScoreRank) as NextTitle,
    SUM(Score) OVER (ORDER BY CreationDate) as CumulativeScore,
    CASE 
        WHEN Score > (SELECT AVG(Score) FROM FinalResult) THEN 'AboveAverage'
        WHEN Score = (SELECT AVG(Score) FROM FinalResult) THEN 'Average'
        ELSE 'BelowAverage'
    END as ScoreCategory,
    CASE 
        WHEN ViewCount > 500 THEN 'HighTraffic'
        WHEN ViewCount >= 100 THEN 'ModerateTraffic'
        WHEN ViewCount > 0 THEN 'LowTraffic'
        ELSE 'NoTraffic'
    END as TrafficLevel,
    ROW_NUMBER() OVER (ORDER BY CreationDate DESC) as ChronologicalRank,
    PERCENT_RANK() OVER (ORDER BY Score DESC) as ScorePercentile,
    CUME_DIST() OVER (ORDER BY Score DESC) as CumulativeDistribution
FROM FinalResult
WHERE ScoreTier IN ('TopScoring', 'HighScoring')
  AND AnswerDensity IN ('FewAnswers', 'ModerateAnswers', 'ManyAnswers')
  AND EngagementLevel IN ('HighEngagement', 'ModerateEngagement')
ORDER BY OverallScoreRank ASC
LIMIT 1000;