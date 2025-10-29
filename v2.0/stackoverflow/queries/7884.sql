-- {"query": "7884.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1950}
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT b.Id) as Badges,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        MAX(p.CreationDate) as LatestPostDate,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) as UpvoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) as DownvoteCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostTypeName,
        CASE 
            WHEN p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY) THEN 'Recent'
            WHEN p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90' DAY) THEN 'Medium'
            ELSE 'Old'
        END as AgeCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as OverallScoreRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgOwnerScore,
        NTILE(4) OVER (ORDER BY p.Score) as ScoreQuartile,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PrevPostScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextPostScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > (SELECT AVG(t2.Count) FROM Tags t2) THEN 'Popular'
            WHEN t.Count < (SELECT AVG(t2.Count) FROM Tags t2) THEN 'Less Popular'
            ELSE 'Average'
        END as PopularityLevel,
        RANK() OVER (ORDER BY t.Count DESC) as PopularityRank,
        PERCENT_RANK() OVER (ORDER BY t.Count DESC) as PopularityPercentile
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName <> ''
),
ComplexPostStats AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.OwnerUserId,
        pa.PostTypeName,
        pa.AgeCategory,
        pa.ScoreRank,
        pa.OverallScoreRank,
        pa.AvgOwnerScore,
        pa.ScoreQuartile,
        pa.PrevPostScore,
        pa.NextPostScore,
        COALESCE(pa.Score - pa.PrevPostScore, 0) as ScoreChangeFromPrev,
        COALESCE(pa.NextPostScore - pa.Score, 0) as ScoreChangeToNext,
        CASE 
            WHEN pa.Score > 0 AND pa.ViewCount > 0 THEN CAST(pa.Score AS numeric) / NULLIF(pa.ViewCount, 0)
            ELSE 0
        END as ScorePerView,
        CASE 
            WHEN pa.Score > 0 AND pa.AnswerCount > 0 THEN CAST(pa.Score AS numeric) / NULLIF(pa.AnswerCount, 0)
            ELSE 0
        END as ScorePerAnswer,
        CASE 
            WHEN pa.CommentCount > 0 THEN 
                CASE 
                    WHEN pa.AnswerCount > 0 THEN (CAST(pa.AnswerCount AS numeric) / NULLIF(pa.CommentCount, 0)) 
                    ELSE 0 
                END
            ELSE 0 
        END as AnswerCommentRatio,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pa.PostId AND c.Score > 0), 
            0
        ) as PositiveComments,
        CASE 
            WHEN pa.Score < 0 AND pa.CommentCount > 0 THEN 
                CAST(pa.Score AS numeric) / NULLIF(pa.CommentCount, 0)
            ELSE 0 
        END as ScorePerComment,
        CASE 
            WHEN pa.AnswerCount > 0 AND pa.PostTypeName = 'Question' THEN 
                (CAST(pa.AnswerCount AS numeric) / NULLIF(pa.ViewCount, 0)) * 100 
            ELSE 0 
        END as AnswerToViewRatio
    FROM PostAnalysis pa
    WHERE pa.PostId IS NOT NULL
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.TotalPosts,
    us.Questions,
    us.Answers,
    us.Badges,
    us.TotalScore,
    us.UpvoteCount,
    us.DownvoteCount,
    us.LatestPostDate,
    CASE 
        WHEN us.TotalPosts > 0 THEN 
            (CASE 
                WHEN us.Questions IS NOT NULL AND us.Questions <> 0 THEN
                    CAST(ROUND((CAST(us.Answers AS numeric) / NULLIF(us.Questions, 0)) * 100::numeric, 2) AS varchar) || '%'
                ELSE
                    '0%'
            END)
        ELSE '0%'
    END as AnswerToQuestionRatio,
    (SELECT COUNT(*) FROM ComplexPostStats cps WHERE cps.OwnerUserId = us.UserId AND cps.PostTypeName = 'Question') as QuestionCount,
    (SELECT COUNT(*) FROM ComplexPostStats cps WHERE cps.OwnerUserId = us.UserId AND cps.PostTypeName = 'Answer') as AnswerCount,
    CASE 
        WHEN us.TotalPosts > 0 THEN 
            (SELECT AVG(cps.Score) FROM ComplexPostStats cps WHERE cps.OwnerUserId = us.UserId)
        ELSE 0 
    END as AverageScore,
    CASE 
        WHEN us.TotalPosts > 0 THEN 
            (SELECT AVG(cps.ScorePerView) FROM ComplexPostStats cps WHERE cps.OwnerUserId = us.UserId)
        ELSE 0 
    END as AvgScorePerView,
    CASE 
        WHEN us.TotalPosts > 0 THEN 
            (SELECT AVG(cps.ScorePerAnswer) FROM ComplexPostStats cps WHERE cps.OwnerUserId = us.UserId)
        ELSE 0 
    END as AvgScorePerAnswer,
    CASE 
        WHEN us.TotalPosts > 0 THEN 
            (SELECT AVG(cps.AnswerToViewRatio) FROM ComplexPostStats cps WHERE cps.OwnerUserId = us.UserId)
        ELSE 0 
    END as AvgAnswerToViewRatio,
    (SELECT MAX(cps.Score) FROM ComplexPostStats cps WHERE cps.OwnerUserId = us.UserId) as TopScore,
    (SELECT MIN(cps.Score) FROM ComplexPostStats cps WHERE cps.OwnerUserId = us.UserId) as BottomScore,
    CASE 
        WHEN us.TotalPosts > 0 THEN 
            (SELECT COUNT(*) FROM ComplexPostStats cps WHERE cps.OwnerUserId = us.UserId AND cps.Score > (SELECT AVG(c2.Score) FROM ComplexPostStats c2))
        ELSE 0 
    END as AboveAvgPosts,
    CASE 
        WHEN us.TotalPosts > 0 THEN 
            (SELECT COUNT(*) FROM ComplexPostStats cps WHERE cps.OwnerUserId = us.UserId AND cps.Score < (SELECT AVG(c2.Score) FROM ComplexPostStats c2))
        ELSE 0 
    END as BelowAvgPosts,
    (SELECT COUNT(*) FROM ComplexPostStats cps WHERE cps.OwnerUserId = us.UserId AND cps.ScoreQuartile = 1) as TopQuartilePosts,
    (SELECT COUNT(*) FROM ComplexPostStats cps WHERE cps.OwnerUserId = us.UserId AND cps.ScoreQuartile = 4) as BottomQuartilePosts,
    (SELECT COUNT(*) FROM ComplexPostStats cps WHERE cps.OwnerUserId = us.UserId AND cps.AgeCategory = 'Recent') as RecentPosts,
    (SELECT COUNT(*) FROM ComplexPostStats cps WHERE cps.OwnerUserId = us.UserId AND cps.AgeCategory = 'Medium') as MediumAgePosts,
    (SELECT COUNT(*) FROM ComplexPostStats cps WHERE cps.OwnerUserId = us.UserId AND cps.AgeCategory = 'Old') as OldPosts
FROM UserStats us
WHERE us.TotalPosts > 0
AND (
    us.TotalPosts >= 10 
    OR us.TotalScore >= 1000 
    OR us.Reputation >= 10000
)
AND (us.Questions > 0 OR us.Answers > 0)
ORDER BY 
    us.TotalScore DESC,
    us.Reputation DESC,
    us.TotalPosts DESC
OFFSET 0
FETCH NEXT 10000 ROWS ONLY;