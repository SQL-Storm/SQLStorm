-- {"query": "7233.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2363} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        DATEDIFF(CURRENT_TIMESTAMP, u.CreationDate) as AccountAgeDays,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Veteran'
            WHEN u.Reputation >= 1000 THEN 'Experienced'
            WHEN u.Reputation >= 100 THEN 'Beginner'
            ELSE 'Newbie'
        END as ReputationLevel,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as RankByReputation,
        PERCENT_RANK() OVER (ORDER BY u.Reputation) as ReputationPercentile,
        AVG(p.Score) as AvgPostScore,
        SUM(p.ViewCount) as TotalViews,
        SUM(p.AnswerCount) as TotalAnswers,
        SUM(p.CommentCount) as TotalComments,
        MAX(CASE WHEN p.PostTypeId = 1 THEN p.Score END) as MaxQuestionScore,
        MAX(CASE WHEN p.PostTypeId = 2 THEN p.Score END) as MaxAnswerScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        *,
        RANK() OVER (ORDER BY TotalPosts DESC) as TopPostsRank,
        RANK() OVER (ORDER BY Questions DESC) as TopQuestionsRank,
        RANK() OVER (ORDER BY Answers DESC) as TopAnswersRank,
        RANK() OVER (ORDER BY Badges DESC) as TopBadgesRank
    FROM UserActivityStats
    WHERE TotalPosts > 0
),
PostTagAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        STRING_TO_ARRAY(
            CASE 
                WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                    SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2)
                ELSE ''
            END, 
            '><'
        ) as TagArray,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        COALESCE(p.CommentCount, 0) as CommentCount,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        CASE 
            WHEN p.Score >= 100 THEN 'Hot'
            WHEN p.Score >= 10 THEN 'Popular'
            WHEN p.Score >= 0 THEN 'Average'
            ELSE 'Low'
        END as PopularityLevel,
        DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) as AgeDays,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2),
            0
        ) as Upvotes,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3),
            0
        ) as Downvotes
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
TagFrequency AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as RankByFrequency,
        AVG(p.Score) as AvgPostScoreForTag,
        MAX(p.CreationDate) as LastUsedDate
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, t.IsModeratorOnly, t.IsRequired
),
ComplexPostAnalysis AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.PostType,
        pa.PopularityLevel,
        pa.AgeDays,
        pa.Upvotes,
        pa.Downvotes,
        pa.TagArray,
        CASE 
            WHEN ARRAY_LENGTH(pa.TagArray) > 0 THEN 
                (SELECT STRING_AGG(tag, ', ') FROM UNNEST(pa.TagArray) as tag)
            ELSE 'No Tags'
        END as TagsList,
        CASE 
            WHEN pa.Score > (SELECT AVG(Score) FROM PostTagAnalysis) 
                 AND pa.ViewCount > (SELECT AVG(ViewCount) FROM PostTagAnalysis)
                 AND pa.AnswerCount > (SELECT AVG(AnswerCount) FROM PostTagAnalysis)
            THEN 'High Performing'
            WHEN pa.Score > 0 OR pa.ViewCount > 0 
                 OR pa.AnswerCount > 0
            THEN 'Moderate Performing'
            ELSE 'Low Performing'
        END as PerformanceCategory,
        DENSE_RANK() OVER (PARTITION BY pa.PostType ORDER BY pa.Score DESC) as ScoreRankWithinType,
        PERCENT_RANK() OVER (ORDER BY pa.Score) as ScorePercentile,
        ABS(pa.Score) as AbsoluteScore,
        SIGN(pa.Score) as ScoreSign
    FROM PostTagAnalysis pa
),
UserPostStats AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.TotalPosts,
        tu.Questions,
        tu.Answers,
        tu.Comments,
        tu.Badges,
        tu.LastPostDate,
        tu.AccountAgeDays,
        tu.ReputationLevel,
        tu.RankByReputation,
        tu.ReputationPercentile,
        tu.AvgPostScore,
        tu.TotalViews,
        tu.TotalAnswers,
        tu.TotalComments,
        tu.MaxQuestionScore,
        tu.MaxAnswerScore,
        CASE 
            WHEN tu.TotalPosts > (SELECT AVG(TotalPosts) FROM TopUsers) * 1.5 THEN 'High Activity'
            WHEN tu.TotalPosts > (SELECT AVG(TotalPosts) FROM TopUsers) THEN 'Above Average'
            ELSE 'Normal Activity'
        END as ActivityLevel,
        ROW_NUMBER() OVER (ORDER BY tu.TotalPosts DESC) as PostCountRank,
        COALESCE(
            (SELECT AVG(p.Score) 
             FROM Posts p 
             WHERE p.OwnerUserId = tu.UserId 
               AND p.PostTypeId = 1), 
            0
        ) as AvgQuestionScore,
        COALESCE(
            (SELECT AVG(p.Score) 
             FROM Posts p 
             WHERE p.OwnerUserId = tu.UserId 
               AND p.PostTypeId = 2), 
            0
        ) as AvgAnswerScore
    FROM TopUsers tu
)
SELECT 
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.TotalPosts,
    up.Questions,
    up.Answers,
    up.Comments,
    up.Badges,
    up.ActivityLevel,
    up.PostCountRank,
    up.AvgPostScore,
    up.AvgQuestionScore,
    up.AvgAnswerScore,
    up.TotalViews,
    up.TotalAnswers,
    up.TotalComments,
    up.MaxQuestionScore,
    up.MaxAnswerScore,
    up.AccountAgeDays,
    up.ReputationLevel,
    up.RankByReputation,
    up.ReputationPercentile,
    (SELECT STRING_AGG(
        CASE 
            WHEN pa.PostType = 'Question' 
            THEN CONCAT(pa.Title, ' (Score: ', pa.Score, ', Tags: ', pa.TagsList, ')')
            ELSE CONCAT('Answer to: ', (
                SELECT Title 
                FROM Posts p2 
                WHERE p2.Id = pa.PostId 
                LIMIT 1
            ), ' (Score: ', pa.Score, ')')
        END, 
        '; ' 
        ORDER BY pa.CreationDate DESC
    ) 
     FROM ComplexPostAnalysis pa 
     WHERE pa.PostId IN (
         SELECT p.Id 
         FROM Posts p 
         WHERE p.OwnerUserId = up.UserId 
           AND p.PostTypeId IN (1, 2)
     )
     LIMIT 5) as RecentActivitySummary,
    (
        SELECT COUNT(*) 
        FROM ComplexPostAnalysis pa 
        WHERE pa.UserId = up.UserId 
          AND pa.AgeDays < 30
    ) as RecentPostsCount,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.UserId = up.UserId 
          AND ph.CreationDate >= DATEADD(DAY, -30, CURRENT_TIMESTAMP)
    ) as RecentEditsCount,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.UserId = up.UserId 
          AND v.CreationDate >= DATEADD(DAY, -30, CURRENT_TIMESTAMP)
    ) as RecentVotesCount,
    COALESCE(
        (SELECT STRING_AGG(b.Name, ', ') 
         FROM Badges b 
         WHERE b.UserId = up.UserId 
           AND b.Date >= DATEADD(YEAR, -1, CURRENT_TIMESTAMP)
         ORDER BY b.Date DESC
        ), 
        'No Recent Badges'
    ) as RecentBadges,
    CASE 
        WHEN up.Reputation >= 10000 AND up.TotalPosts >= 100 
        THEN 'Elite Contributor'
        WHEN up.Reputation >= 1000 AND up.TotalPosts >= 50 
        THEN 'Experienced Contributor'
        WHEN up.Reputation >= 100 AND up.TotalPosts >= 10 
        THEN 'Active Contributor'
        ELSE 'Contributor'
    END as ContributorTier,
    (
        SELECT STRING_AGG(
            CONCAT(
                'Tag: ', t.TagName, 
                ' (Count: ', t.TagCount, ')'
            ), 
            '; '
        ) 
        FROM Tags t
        WHERE t.TagName IN (
            SELECT UNNEST(pa.TagArray) 
            FROM ComplexPostAnalysis pa 
            WHERE pa.UserId = up.UserId
        )
        ORDER BY t.Count DESC
        LIMIT 5
    ) as PopularTags,
    GREATEST(
        up.Reputation,
        up.TotalPosts,
        up.Questions,
        up.Answers
    ) as MaxMetricsScore
FROM UserPostStats up
WHERE up.Reputation >= 1000
  AND up.TotalPosts >= 10
  AND (up.Questions >= 1 OR up.Answers >= 1)
ORDER BY up.Reputation DESC, up.TotalPosts DESC
LIMIT 100;