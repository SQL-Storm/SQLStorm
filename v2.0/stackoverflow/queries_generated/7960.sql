-- {"query": "7960.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2823} 
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
        MAX(c.CreationDate) as LastCommentDate,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
        RANK() OVER (ORDER BY u.Reputation DESC) as RepRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        Questions,
        Answers,
        Comments,
        Badges,
        LastPostDate,
        LastCommentDate,
        PostRank,
        RepRank,
        CASE 
            WHEN TotalPosts > 1000 AND Reputation > 10000 THEN 'Elite'
            WHEN TotalPosts > 500 AND Reputation > 5000 THEN 'Veteran'
            WHEN TotalPosts > 100 THEN 'Active'
            ELSE 'Regular'
        END as UserCategory,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) as ReputationRank,
        NTILE(10) OVER (ORDER BY Reputation) as ReputationDecile
    FROM UserActivityStats
    WHERE TotalPosts > 0
),
PostComplexity AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        p.PostTypeId,
        LEN(p.Body) as BodyLength,
        (LEN(p.Body) - LEN(REPLACE(p.Body, '<', ''))) as HtmlTagCount,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                CASE 
                    WHEN p.AnswerCount > 0 THEN 
                        CASE 
                            WHEN p.ViewCount > 1000 THEN 'HighlyViewed'
                            WHEN p.ViewCount > 100 THEN 'ModeratelyViewed'
                            ELSE 'LowViewed'
                        END
                    ELSE 'NoAnswers'
                END
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostComplexity,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgUserScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostSequence,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2) as AnswerCountWithFilter,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                (SELECT COUNT(*) FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag)
            ELSE 0 
        END as TagCount,
        CASE 
            WHEN p.Score >= 100 THEN 'Popular'
            WHEN p.Score >= 10 THEN 'Moderate'
            WHEN p.Score >= 0 THEN 'Neutral'
            ELSE 'Negative'
        END as ScoreCategory,
        DATEDIFF(day, p.CreationDate, CURRENT_TIMESTAMP) as DaysSinceCreation
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
),
UserPostAnalysis AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.PostRank,
        tu.RepRank,
        tu.TotalPosts,
        tu.Questions,
        tu.Answers,
        tu.Comments,
        tu.Badges,
        tu.UserCategory,
        tu.ReputationRank,
        tu.ReputationDecile,
        AVG(p.Score) as AvgPostScore,
        MAX(p.Score) as MaxPostScore,
        MIN(p.Score) as MinPostScore,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) as QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) as AnswerCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END) as AvgQuestionViewCount,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount END) as AvgAnswerViewCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCountWithVotes,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCountWithVotes,
        STRING_AGG(DISTINCT p.Title, '; ') as UserPostTitles,
        STRING_AGG(CASE WHEN p.PostTypeId = 1 THEN p.Title ELSE NULL END, '; ') as UserQuestionTitles,
        STRING_AGG(CASE WHEN p.PostTypeId = 2 THEN p.Title ELSE NULL END, '; ') as UserAnswerTitles,
        (
            SELECT STRING_AGG(b.Name, ', ')
            FROM Badges b 
            WHERE b.UserId = tu.UserId 
            AND b.Class = 1
        ) as GoldBadges,
        (
            SELECT STRING_AGG(b.Name, ', ')
            FROM Badges b 
            WHERE b.UserId = tu.UserId 
            AND b.Class = 2
        ) as SilverBadges,
        (
            SELECT STRING_AGG(b.Name, ', ')
            FROM Badges b 
            WHERE b.UserId = tu.UserId 
            AND b.Class = 3
        ) as BronzeBadges,
        (
            SELECT COUNT(*)
            FROM Votes v 
            WHERE v.UserId = tu.UserId 
            AND v.VoteTypeId = 2
        ) as UpvotesGiven,
        (
            SELECT COUNT(*)
            FROM Votes v 
            WHERE v.UserId = tu.UserId 
            AND v.VoteTypeId = 3
        ) as DownvotesGiven,
        (
            SELECT MAX(v.CreationDate)
            FROM Votes v 
            WHERE v.UserId = tu.UserId 
            AND v.VoteTypeId IN (2,3)
        ) as LastVoteDate,
        (
            SELECT AVG(v.CreationDate) - MIN(v.CreationDate)
            FROM Votes v 
            WHERE v.UserId = tu.UserId 
            AND v.VoteTypeId IN (2,3)
        ) as VoteActivitySpan,
        NULLIF(
            (SELECT COUNT(DISTINCT p2.Id) 
             FROM Posts p2 
             WHERE p2.OwnerUserId = tu.UserId 
             AND p2.PostTypeId = 1 
             AND p2.AnswerCount > 0),
            0
        ) as QuestionsWithAnswers
    FROM TopUsers tu
    LEFT JOIN Posts p ON tu.UserId = p.OwnerUserId
    GROUP BY 
        tu.UserId, tu.DisplayName, tu.Reputation, tu.PostRank, 
        tu.RepRank, tu.TotalPosts, tu.Questions, tu.Answers, 
        tu.Comments, tu.Badges, tu.UserCategory, tu.ReputationRank, 
        tu.ReputationDecile
)
SELECT 
    upa.UserId,
    upa.DisplayName,
    upa.Reputation,
    upa.PostRank,
    upa.RepRank,
    upa.TotalPosts,
    upa.Questions,
    upa.Answers,
    upa.Comments,
    upa.Badges,
    upa.UserCategory,
    upa.ReputationRank,
    upa.ReputationDecile,
    upa.AvgPostScore,
    upa.MaxPostScore,
    upa.MinPostScore,
    upa.QuestionCount,
    upa.AnswerCount,
    upa.AvgQuestionViewCount,
    upa.AvgAnswerViewCount,
    upa.QuestionCountWithVotes,
    upa.AnswerCountWithVotes,
    upa.UserPostTitles,
    upa.UserQuestionTitles,
    upa.UserAnswerTitles,
    upa.GoldBadges,
    upa.SilverBadges,
    upa.BronzeBadges,
    upa.UpvotesGiven,
    upa.DownvotesGiven,
    upa.LastVoteDate,
    upa.VoteActivitySpan,
    upa.QuestionsWithAnswers,
    CASE 
        WHEN upa.Questions > 50 AND upa.Answers > 100 THEN 'Active Contributor'
        WHEN upa.Questions > 10 AND upa.Answers > 20 THEN 'Contributor'
        WHEN upa.TotalPosts > 100 THEN 'Regular User'
        WHEN upa.TotalPosts > 50 THEN 'Engaged User'
        WHEN upa.TotalPosts > 10 THEN 'Occasional User'
        ELSE 'New User'
    END as ActivityLevel,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p1 
         WHERE p1.OwnerUserId = upa.UserId 
         AND p1.PostTypeId = 1 
         AND p1.CreationDate >= DATEADD(month, -6, CURRENT_TIMESTAMP)),
        0
    ) as RecentQuestions,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p1 
         WHERE p1.OwnerUserId = upa.UserId 
         AND p1.PostTypeId = 2 
         AND p1.CreationDate >= DATEADD(month, -6, CURRENT_TIMESTAMP)),
        0
    ) as RecentAnswers,
    ROW_NUMBER() OVER (ORDER BY upa.Reputation DESC) as GlobalRank,
    PERCENT_RANK() OVER (ORDER BY upa.Reputation) as RepPercentile,
    ROUND(
        (upa.Reputation * 1.0) / NULLIF((SELECT MAX(Reputation) FROM Users), 0) * 100, 
        2
    ) as ReputationPercentage,
    CASE 
        WHEN upa.Reputation >= 100000 THEN 'Legendary'
        WHEN upa.Reputation >= 50000 THEN 'Master'
        WHEN upa.Reputation >= 25000 THEN 'Expert'
        WHEN upa.Reputation >= 10000 THEN 'Advanced'
        WHEN upa.Reputation >= 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END as RepTier,
    IIF(upa.Questions > 0, (upa.Answers * 1.0) / upa.Questions, 0) as AnswerToQuestionRatio,
    IIF(upa.Answers > 0, (upa.QuestionCountWithVotes * 1.0) / upa.Answers, 0) as VoteToAnswerRatio,
    (upa.Reputation + upa.TotalPosts * 5 + upa.Answers * 10 + upa.Questions * 15) as CompositeScore,
    IIF(
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.UserId = upa.UserId 
         AND v.VoteTypeId = 2 
         AND v.CreationDate >= DATEADD(day, -30, CURRENT_TIMESTAMP)) > 50,
        'High Engagement',
        'Moderate Engagement'
    ) as EngagementLevel,
    IIF(
        upa.TotalPosts > 100 AND upa.Reputation > 5000,
        'Influential',
        'Standard'
    ) as InfluenceLevel,
    COALESCE(
        (SELECT COUNT(DISTINCT p3.Id) 
         FROM Posts p3 
         WHERE p3.OwnerUserId = upa.UserId 
         AND p3.PostTypeId IN (1,2) 
         AND p3.Tags IS NOT NULL 
         AND p3.Tags != ''),
        0
    ) as TaggedPosts
FROM UserPostAnalysis upa
WHERE upa.TotalPosts >= 10
  AND upa.UserId IN (
    SELECT DISTINCT UserId 
    FROM Posts 
    WHERE OwnerUserId IS NOT NULL
    EXCEPT
    SELECT DISTINCT UserId 
    FROM Votes 
    WHERE VoteTypeId IN (1,2,3,5,6,7,8,9,10,11,12,14,15,16)
    GROUP BY UserId
    HAVING COUNT(*) >= 1000
  )
  AND (
    upa.GoldBadges IS NOT NULL 
    OR upa.SilverBadges IS NOT NULL 
    OR upa.BronzeBadges IS NOT NULL
  )
  AND EXISTS (
    SELECT 1 FROM Posts p 
    WHERE p.OwnerUserId = upa.UserId 
    AND p.CreationDate >= DATEADD(year, -2, CURRENT_TIMESTAMP)
  )
  AND NOT (
    upa.Reputation < 100 
    AND upa.Questions = 0 
    AND upa.Answers = 0
  )
ORDER BY upa.Reputation DESC, upa.TotalPosts DESC
OFFSET 0 ROWS
FETCH NEXT 500 ROWS ONLY;