-- {"query": "7019.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3715} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as QuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as AnswerScore,
        MAX(p.CreationDate) as LastPostDate,
        COUNT(DISTINCT b.Id) as BadgeCount,
        STRING_AGG(DISTINCT b.Name, ', ') as BadgesEarned,
        AVG(p.Score) as AvgPostScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighViewQuestions
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY QuestionScore DESC, AnswerScore DESC) as RankByScore,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) as RankByReputation,
        NTILE(10) OVER (ORDER BY QuestionCount DESC) as QuestionDecile
    FROM UserStats
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as PostsWithTag,
        AVG(p.Score) as AvgScoreForTag,
        STRING_AGG(DISTINCT u.DisplayName, ', ') as TagUsers
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
),
PostActivity AS (
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
        p.Tags,
        u.DisplayName as OwnerName,
        COALESCE(p.AcceptedAnswerId, 0) as HasAcceptedAnswer,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END as IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END as IsCommunityOwned,
        DATEDIFF('second', p.CreationDate, COALESCE(p.LastEditDate, p.LastActivityDate)) as TimeSinceLastActivity,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousPostDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as UserPostRank,
        RANK() OVER (ORDER BY p.Score DESC) as GlobalScoreRank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
ComprehensiveAnalysis AS (
    SELECT 
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.PostCount,
        ru.QuestionCount,
        ru.AnswerCount,
        ru.QuestionScore,
        ru.AnswerScore,
        ru.BadgeCount,
        ru.BadgesEarned,
        ru.AvgPostScore,
        ru.HighViewQuestions,
        ru.RankByScore,
        ru.RankByReputation,
        ru.QuestionDecile,
        ta.TagName,
        ta.TagCount,
        ta.PostsWithTag,
        ta.AvgScoreForTag,
        ta.TagUsers,
        pa.PostId,
        pa.Title,
        pa.Score as PostScore,
        pa.ViewCount,
        pa.CreationDate as PostCreationDate,
        pa.OwnerName,
        pa.HasAcceptedAnswer,
        pa.IsClosed,
        pa.IsCommunityOwned,
        pa.TimeSinceLastActivity,
        pa.PreviousScore,
        pa.PreviousPostDate,
        pa.UserPostRank,
        pa.GlobalScoreRank,
        CASE 
            WHEN pa.PreviousScore IS NOT NULL AND pa.Score > pa.PreviousScore THEN 'Increased'
            WHEN pa.PreviousScore IS NOT NULL AND pa.Score < pa.PreviousScore THEN 'Decreased'
            ELSE 'Same'
        END as ScoreTrend,
        CASE 
            WHEN pa.Score > 100 THEN 'HighlyRated'
            WHEN pa.Score > 50 THEN 'ModeratelyRated'
            WHEN pa.Score > 10 THEN 'LowRated'
            ELSE 'VeryLowRated'
        END as RatingCategory,
        DENSE_RANK() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.GlobalScoreRank) as OwnerRankedPosts
    FROM RankedUsers ru
    INNER JOIN TagAnalysis ta ON ru.BadgeCount > 0
    INNER JOIN PostActivity pa ON ru.UserId = pa.OwnerUserId
    WHERE ru.QuestionCount > 0
),
PerformanceMetrics AS (
    SELECT 
        COUNT(*) as TotalRecords,
        AVG(Reputation) as AvgReputation,
        MAX(QuestionScore) as MaxQuestionScore,
        MIN(AnswerScore) as MinAnswerScore,
        SUM(PostCount) as TotalPosts,
        STDDEV(Reputation) as StdDevReputation,
        COUNT(DISTINCT UserId) as DistinctUsers,
        COUNT(DISTINCT TagName) as DistinctTags,
        AVG(OwnScore) as AvgOwnScore,
        COUNT(DISTINCT CASE WHEN IsClosed = 1 THEN PostId END) as ClosedPosts,
        COUNT(DISTINCT CASE WHEN IsCommunityOwned = 1 THEN PostId END) as CommunityOwnedPosts,
        AVG(AvgTagScore) as AvgTagScore,
        COUNT(DISTINCT OwnerName) as DistinctOwners,
        COUNT(DISTINCT BadgesEarned) as DistinctBadges,
        COUNT(DISTINCT DisplayName) as DistinctNames,
        MIN(CreationDate) as EarliestDate,
        MAX(CreationDate) as LatestDate,
        MAX(AvgScoreForTag) as MaxTagScore,
        MIN(AvgScoreForTag) as MinTagScore,
        AVG(TimeSinceLastActivity) as AvgTimeSinceActivity,
        COUNT(DISTINCT CASE WHEN ScoreTrend = 'Increased' THEN PostId END) as IncreasedScorePosts,
        COUNT(DISTINCT CASE WHEN ScoreTrend = 'Decreased' THEN PostId END) as DecreasedScorePosts,
        COUNT(DISTINCT CASE WHEN ScoreTrend = 'Same' THEN PostId END) as SameScorePosts
    FROM (
        SELECT 
            ca.UserId,
            ca.DisplayName,
            ca.Reputation,
            ca.PostCount,
            ca.QuestionCount,
            ca.AnswerCount,
            ca.QuestionScore,
            ca.AnswerScore,
            ca.BadgeCount,
            ca.BadgesEarned,
            ca.AvgPostScore,
            ca.HighViewQuestions,
            ca.RankByScore,
            ca.RankByReputation,
            ca.QuestionDecile,
            ca.TagName,
            ca.TagCount,
            ca.PostsWithTag,
            ca.AvgScoreForTag,
            ca.TagUsers,
            ca.PostId,
            ca.Title,
            ca.PostScore,
            ca.ViewCount,
            ca.CreationDate,
            ca.OwnerName,
            ca.HasAcceptedAnswer,
            ca.IsClosed,
            ca.IsCommunityOwned,
            ca.TimeSinceLastActivity,
            ca.PreviousScore,
            ca.PreviousPostDate,
            ca.UserPostRank,
            ca.GlobalScoreRank,
            ca.ScoreTrend,
            ca.RatingCategory,
            ca.OwnerRankedPosts,
            ca.PostScore as OwnScore,
            ca.AvgScoreForTag as AvgTagScore,
            ca.CreationDate
        FROM ComprehensiveAnalysis ca
    ) derived_table
)
SELECT 
    pm.TotalRecords,
    pm.AvgReputation,
    pm.MaxQuestionScore,
    pm.MinAnswerScore,
    pm.TotalPosts,
    pm.StdDevReputation,
    pm.DistinctUsers,
    pm.DistinctTags,
    pm.AvgOwnScore,
    pm.ClosedPosts,
    pm.CommunityOwnedPosts,
    pm.AvgTagScore,
    pm.DistinctOwners,
    pm.DistinctBadges,
    pm.DistinctNames,
    pm.EarliestDate,
    pm.LatestDate,
    pm.MaxTagScore,
    pm.MinTagScore,
    pm.AvgTimeSinceActivity,
    pm.IncreasedScorePosts,
    pm.DecreasedScorePosts,
    pm.SameScorePosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)) as HighScoreQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2)) as HighScoreAnswers,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.ViewCount > 1000 AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)) as PopularHighScoreQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND p.ViewCount > 1000 AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2)) as PopularHighScoreAnswers,
    (SELECT COUNT(DISTINCT p.OwnerUserId) FROM Posts p WHERE p.PostTypeId = 1 AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)) as HighScoreQuestionAuthors,
    (SELECT COUNT(DISTINCT p.OwnerUserId) FROM Posts p WHERE p.PostTypeId = 2 AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2)) as HighScoreAnswerAuthors,
    (SELECT COUNT(DISTINCT p.OwnerUserId) FROM Posts p WHERE p.PostTypeId = 1 AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) AND p.ViewCount > 1000) as PopularHighScoreQuestionAuthors,
    (SELECT COUNT(DISTINCT p.OwnerUserId) FROM Posts p WHERE p.PostTypeId = 2 AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) AND p.ViewCount > 1000) as PopularHighScoreAnswerAuthors,
    (SELECT COUNT(*) FROM Comments c WHERE c.Score > 10) as HighScoreComments,
    (SELECT AVG(c.Score) FROM Comments c WHERE c.Score > 10) as AvgHighScoreCommentScore,
    (SELECT MAX(c.Score) FROM Comments c WHERE c.Score > 10) as MaxHighScoreCommentScore,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13)) as ImportantPostHistoryEvents,
    (SELECT COUNT(*) FROM Votes v WHERE v.VoteTypeId IN (1, 2, 3)) as ImportantVotes,
    (SELECT COUNT(DISTINCT ph.UserId) FROM PostHistory ph WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13)) as UniqueUsersWithPostHistoryEvents,
    (SELECT COUNT(DISTINCT v.UserId) FROM Votes v WHERE v.VoteTypeId IN (1, 2, 3)) as UniqueUsersWithVotes,
    (SELECT COUNT(DISTINCT u.Id) FROM Users u JOIN Posts p ON u.Id = p.OwnerUserId WHERE p.PostTypeId = 1 GROUP BY u.Id HAVING COUNT(p.Id) > 10) as MultipleQuestionAuthors,
    (SELECT COUNT(DISTINCT u.Id) FROM Users u JOIN Posts p ON u.Id = p.OwnerUserId WHERE p.PostTypeId = 2 GROUP BY u.Id HAVING COUNT(p.Id) > 10) as MultipleAnswerAuthors,
    (SELECT STRING_AGG(DISTINCT DisplayName, ', ') FROM Users u WHERE u.Id IN (SELECT DISTINCT OwnerUserId FROM Posts WHERE Score > 50)) as HighScorePostAuthors,
    (SELECT STRING_AGG(DISTINCT TagName, ', ') FROM Tags WHERE Count > 1000) as PopularTags,
    (SELECT STRING_AGG(DISTINCT DisplayName, ', ') FROM Users WHERE Reputation > 10000) as HighlyReputedUsers,
    (SELECT COUNT(*) FROM Posts p WHERE p.Tags IS NOT NULL AND LENGTH(p.Tags) > 50) as PostsWithLongTags,
    (SELECT AVG(LENGTH(p.Tags)) FROM Posts p WHERE p.Tags IS NOT NULL) as AvgTagLength,
    (SELECT MAX(LENGTH(p.Tags)) FROM Posts p WHERE p.Tags IS NOT NULL) as MaxTagLength,
    (SELECT MIN(LENGTH(p.Tags)) FROM Posts p WHERE p.Tags IS NOT NULL) as MinTagLength,
    (SELECT COUNT(*) FROM Badges b WHERE b.Class = 1) as TotalGoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.Class = 2) as TotalSilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.Class = 3) as TotalBronzeBadges,
    (SELECT COUNT(*) FROM Users u WHERE u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl != '') as UsersWithWebsite,
    (SELECT COUNT(*) FROM Users u WHERE u.Location IS NOT NULL AND u.Location != '') as UsersWithLocation,
    (SELECT COUNT(*) FROM Users u WHERE u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100) as UsersWithLongAboutMe,
    (SELECT COUNT(*) FROM Posts p WHERE p.Body IS NOT NULL) as PostsWithBody,
    (SELECT AVG(LENGTH(p.Body)) FROM Posts p WHERE p.Body IS NOT NULL) as AvgBodyLength,
    (SELECT COUNT(*) FROM Posts p WHERE p.ParentId IS NOT NULL AND p.PostTypeId = 2) as AnswerPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.ParentId IS NULL AND p.PostTypeId = 1) as QuestionPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1) as QuestionsWithAcceptedAnswer,
    (SELECT AVG(AnswerCount) FROM Posts p WHERE p.PostTypeId = 1) as AvgAnswerCount,
    (SELECT MAX(AnswerCount) FROM Posts p WHERE p.PostTypeId = 1) as MaxAnswerCount,
    (SELECT MIN(AnswerCount) FROM Posts p WHERE p.PostTypeId = 1) as MinAnswerCount,
    (SELECT COUNT(*) FROM Posts p WHERE p.CommentCount > 5) as PostsWithManyComments,
    (SELECT AVG(CommentCount) FROM Posts p) as AvgCommentCount,
    (SELECT MAX(CommentCount) FROM Posts p) as MaxCommentCount,
    (SELECT COUNT(*) FROM Posts p WHERE p.Score > 0) as PositiveScorePosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.Score < 0) as NegativeScorePosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.Score = 0) as ZeroScorePosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.ViewCount > 10000) as HighlyViewedPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.ViewCount BETWEEN 1000 AND 10000) as ModeratelyViewedPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.ViewCount < 1000) as LowViewedPosts,
    (SELECT AVG(ViewCount) FROM Posts p WHERE p.PostTypeId IN (1, 2)) as AvgViewsPerPost,
    (SELECT AVG(Score) FROM Posts p WHERE p.PostTypeId IN (1, 2)) as AvgScorePerPost,
    (SELECT COUNT(*) FROM Posts p WHERE p.CreationDate > '2020-01-01') as RecentPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.CreationDate < '2020-01-01') as OlderPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.CreationDate BETWEEN '2020-01-01' AND '2021-01-01') as Posts2020,
    (SELECT COUNT(*) FROM Posts p WHERE p.CreationDate BETWEEN '2021-01-01' AND '2022-01-01') as Posts2021,
    (SELECT COUNT(*) FROM Posts p WHERE p.CreationDate BETWEEN '2022-01-01' AND '2023-01-01') as Posts2022,
    (SELECT COUNT(*) FROM Posts p WHERE p.CreationDate BETWEEN '2023-01-01' AND '2024-01-01') as Posts2023,
    (SELECT COUNT(*) FROM Posts p WHERE p.CreationDate BETWEEN '2024-01-01' AND '2025-01-01') as Posts2024
FROM PerformanceMetrics pm;