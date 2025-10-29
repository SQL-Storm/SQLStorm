-- {"query": "7947.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3070} 
WITH RECURSIVE PostHierarchy AS (
    SELECT Id, ParentId, PostTypeId, OwnerUserId, Score, ViewCount, Title, 
           0 as Depth, CAST(Id AS VARCHAR(1000)) as Path
    FROM Posts 
    WHERE PostTypeId = 1 AND ParentId IS NULL
    
    UNION ALL
    
    SELECT p.Id, p.ParentId, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, p.Title,
           ph.Depth + 1, ph.Path || ',' || CAST(p.Id AS VARCHAR)
    FROM Posts p
    INNER JOIN PostHierarchy ph ON p.ParentId = ph.Id
    WHERE ph.Depth < 5
),
UserStats AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes,
           COUNT(DISTINCT b.Id) as TotalBadges,
           COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
           COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
           COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
           AVG(CAST(p.Score AS FLOAT)) as AvgPostScore,
           COUNT(DISTINCT p.Id) as PostCount,
           STRING_AGG(DISTINCT p.Title, '; ') as PostTitles
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagStats AS (
    SELECT t.TagName, t.Count, 
           AVG(CAST(p.Score AS FLOAT)) as AvgScore, 
           COUNT(DISTINCT p.Id) as PostCount,
           STRING_AGG(DISTINCT p.Title, '; ') as PostTitles
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName, t.Count
),
PostAnalysis AS (
    SELECT p.Id, p.Title, p.Score, p.ViewCount, p.OwnerUserId, p.CreationDate, p.Tags,
           CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END as HasAcceptedAnswer,
           CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END as IsClosed,
           CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END as IsCommunityOwned,
           DATEDIFF(day, p.CreationDate, COALESCE(p.ClosedDate, CURRENT_TIMESTAMP)) as DaysOpen,
           COALESCE(p.AnswerCount, 0) as AnswerCount,
           COALESCE(p.CommentCount, 0) as CommentCount,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as UserPostRank,
           AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as OwnerAvgScore,
           RANK() OVER (ORDER BY p.Score DESC) as GlobalScoreRank,
           DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
           NTILE(100) OVER (ORDER BY p.Score ASC) as ScorePercentile,
           CASE WHEN p.Score > (SELECT AVG(Score) FROM Posts) THEN 'AboveAvg' 
                WHEN p.Score < (SELECT AVG(Score) FROM Posts) THEN 'BelowAvg' 
                ELSE 'Avg' END as ScoreCategory
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.Score IS NOT NULL AND p.ViewCount IS NOT NULL
),
ComplexVoterAnalysis AS (
    SELECT v.PostId, 
           COUNT(v.Id) as VoteCount,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as UpVotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) as DownVotes,
           SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) as FavoriteVotes,
           AVG(CAST(v.BountyAmount AS FLOAT)) as AvgBountyAmount,
           STRING_AGG(v.UserId::VARCHAR, ',') as VoterIds,
           STRING_AGG(CASE WHEN v.UserId IS NOT NULL THEN u.DisplayName ELSE 'Anonymous' END, ', ') as VoterNames
    FROM Votes v
    LEFT JOIN Users u ON v.UserId = u.Id
    WHERE v.VoteTypeId IN (2, 3, 5) AND v.PostId IN (SELECT Id FROM Posts WHERE PostTypeId = 1)
    GROUP BY v.PostId
)
SELECT 
    'Post Analysis Report' as ReportName,
    COUNT(*) as TotalPosts,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1) as TotalQuestions,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2) as TotalAnswers,
    (SELECT AVG(Score) FROM Posts WHERE PostTypeId IN (1, 2)) as OverallAvgScore,
    (SELECT COUNT(*) FROM Posts WHERE ClosedDate IS NOT NULL) as ClosedPosts,
    (SELECT COUNT(*) FROM Posts WHERE CommunityOwnedDate IS NOT NULL) as CommunityOwnedPosts,
    (SELECT COUNT(*) FROM Posts WHERE ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE ViewCount IS NOT NULL)) as HighViewCountPosts,
    (SELECT STRING_AGG(TagName, ', ') FROM Tags WHERE Count > (SELECT AVG(Count) FROM Tags WHERE Count IS NOT NULL)) as PopularTags,
    (SELECT COUNT(*) FROM (SELECT DISTINCT OwnerUserId FROM Posts WHERE Score > 1000) as HighScoreUsers) as HighScoringUsers,
    (SELECT COUNT(*) FROM Posts p WHERE EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = p.Id)) as PostsWithComments,
    (SELECT COUNT(*) FROM Posts p WHERE EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20))) as PostsWithHistoryEvents,
    (SELECT COUNT(*) FROM Users u WHERE EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.Score > 1000)) as UsersWithHighScorePosts,
    (SELECT COUNT(*) FROM Badges b WHERE EXISTS (SELECT 1 FROM Users u WHERE u.Id = b.UserId AND u.Reputation > 10000)) as BadgesFromReputableUsers,
    (SELECT COUNT(*) FROM (SELECT OwnerUserId, COUNT(*) as PostsWithAvgScore FROM Posts WHERE Score IS NOT NULL GROUP BY OwnerUserId HAVING COUNT(*) > 5) as HighPostCountUsers) as UsersWithManyPosts,
    (SELECT COUNT(*) FROM (SELECT PostId, COUNT(*) as VoteCount FROM Votes WHERE VoteTypeId IN (2, 3, 5) GROUP BY PostId HAVING COUNT(*) > 50) as HighlyVotedPosts) as HighlyVotedPosts,
    (SELECT COUNT(*) FROM (SELECT Id FROM Posts WHERE Tags IS NOT NULL AND Tags != '') as TaggedPosts) as TaggedPosts,
    (SELECT COUNT(*) FROM (SELECT Id FROM Posts WHERE Body IS NOT NULL AND LENGTH(Body) > 1000) as LongPosts) as LongPosts,
    (SELECT COUNT(*) FROM (SELECT p.Id FROM Posts p INNER JOIN PostLinks pl ON p.Id = pl.PostId WHERE pl.LinkTypeId = 3) as DuplicatePosts) as DuplicateLinkedPosts,
    (SELECT COUNT(*) FROM (SELECT UserId FROM Votes WHERE VoteTypeId IN (2, 3) GROUP BY UserId HAVING COUNT(*) > 1000) as ActiveVoters) as ActiveVoters,
    (SELECT COUNT(*) FROM Comments WHERE Text IS NOT NULL AND LENGTH(Text) > 100) as LongComments,
    (SELECT COUNT(*) FROM PostHistory WHERE Text IS NOT NULL AND LENGTH(Text) > 500) as LongHistoryTexts,
    (SELECT COUNT(*) FROM Users WHERE DisplayName IS NOT NULL AND DisplayName != '') as UsersWithDisplayNames,
    (SELECT COUNT(*) FROM Posts WHERE Body LIKE '%<code>%' OR Body LIKE '%`%`%') as CodePosts,
    (SELECT COUNT(*) FROM Posts WHERE Body LIKE '%<p>%</p>%' OR Body LIKE '%<div>%' OR Body LIKE '%<span>%</span>%') as HTMLFormattedPosts,
    (SELECT COUNT(*) FROM Tags WHERE TagName LIKE '%-%' AND TagName NOT LIKE '%%') as HyphenatedTags,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND AnswerCount > 10) as QuestionsWithManyAnswers,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND CommentCount > 5) as QuestionsWithManyComments,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND FavoriteCount > 10) as QuestionsWithManyFavorites,
    NULL as NullValuePlaceholder
FROM Posts
HAVING COUNT(*) > 0
UNION ALL
SELECT 
    'User Statistics Summary' as ReportName,
    COUNT(*) as TotalPosts,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1) as TotalQuestions,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2) as TotalAnswers,
    (SELECT AVG(Score) FROM Posts WHERE PostTypeId IN (1, 2)) as OverallAvgScore,
    (SELECT COUNT(*) FROM Posts WHERE ClosedDate IS NOT NULL) as ClosedPosts,
    (SELECT COUNT(*) FROM Posts WHERE CommunityOwnedDate IS NOT NULL) as CommunityOwnedPosts,
    (SELECT COUNT(*) FROM Posts WHERE ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE ViewCount IS NOT NULL)) as HighViewCountPosts,
    NULL as PopularTags,
    NULL as HighScoringUsers,
    (SELECT COUNT(*) FROM Posts p WHERE EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = p.Id)) as PostsWithComments,
    (SELECT COUNT(*) FROM Posts p WHERE EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20))) as PostsWithHistoryEvents,
    NULL as UsersWithHighScorePosts,
    (SELECT COUNT(*) FROM Badges b WHERE EXISTS (SELECT 1 FROM Users u WHERE u.Id = b.UserId AND u.Reputation > 10000)) as BadgesFromReputableUsers,
    NULL as UsersWithManyPosts,
    (SELECT COUNT(*) FROM (SELECT PostId, COUNT(*) as VoteCount FROM Votes WHERE VoteTypeId IN (2, 3, 5) GROUP BY PostId HAVING COUNT(*) > 50) as HighlyVotedPosts) as HighlyVotedPosts,
    (SELECT COUNT(*) FROM (SELECT Id FROM Posts WHERE Tags IS NOT NULL AND Tags != '') as TaggedPosts) as TaggedPosts,
    (SELECT COUNT(*) FROM (SELECT Id FROM Posts WHERE Body IS NOT NULL AND LENGTH(Body) > 1000) as LongPosts) as LongPosts,
    (SELECT COUNT(*) FROM (SELECT p.Id FROM Posts p INNER JOIN PostLinks pl ON p.Id = pl.PostId WHERE pl.LinkTypeId = 3) as DuplicatePosts) as DuplicateLinkedPosts,
    (SELECT COUNT(*) FROM (SELECT UserId FROM Votes WHERE VoteTypeId IN (2, 3) GROUP BY UserId HAVING COUNT(*) > 1000) as ActiveVoters) as ActiveVoters,
    (SELECT COUNT(*) FROM Comments WHERE Text IS NOT NULL AND LENGTH(Text) > 100) as LongComments,
    (SELECT COUNT(*) FROM PostHistory WHERE Text IS NOT NULL AND LENGTH(Text) > 500) as LongHistoryTexts,
    (SELECT COUNT(*) FROM Users WHERE DisplayName IS NOT NULL AND DisplayName != '') as UsersWithDisplayNames,
    (SELECT COUNT(*) FROM Posts WHERE Body LIKE '%<code>%' OR Body LIKE '%`%`%') as CodePosts,
    (SELECT COUNT(*) FROM Posts WHERE Body LIKE '%<p>%</p>%' OR Body LIKE '%<div>%' OR Body LIKE '%<span>%</span>%') as HTMLFormattedPosts,
    (SELECT COUNT(*) FROM Tags WHERE TagName LIKE '%-%' AND TagName NOT LIKE '%%') as HyphenatedTags,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND AnswerCount > 10) as QuestionsWithManyAnswers,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND CommentCount > 5) as QuestionsWithManyComments,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND FavoriteCount > 10) as QuestionsWithManyFavorites,
    NULL as NullValuePlaceholder
FROM Users
WHERE EXISTS (SELECT 1 FROM Posts WHERE OwnerUserId = Users.Id)
HAVING COUNT(*) > 0
UNION ALL
SELECT 
    'Tag Statistics Summary' as ReportName,
    0 as TotalPosts,
    0 as TotalQuestions,
    0 as TotalAnswers,
    0 as OverallAvgScore,
    0 as ClosedPosts,
    0 as CommunityOwnedPosts,
    0 as HighViewCountPosts,
    NULL as PopularTags,
    NULL as HighScoringUsers,
    0 as PostsWithComments,
    0 as PostsWithHistoryEvents,
    0 as UsersWithHighScorePosts,
    0 as BadgesFromReputableUsers,
    0 as UsersWithManyPosts,
    0 as HighlyVotedPosts,
    0 as TaggedPosts,
    0 as LongPosts,
    0 as DuplicateLinkedPosts,
    0 as ActiveVoters,
    0 as LongComments,
    0 as LongHistoryTexts,
    0 as UsersWithDisplayNames,
    0 as CodePosts,
    0 as HTMLFormattedPosts,
    0 as HyphenatedTags,
    0 as QuestionsWithManyAnswers,
    0 as QuestionsWithManyComments,
    0 as QuestionsWithManyFavorites,
    STRING_AGG(SUBSTRING(TagName, 1, 50), ', ') as NullValuePlaceholder
FROM Tags
WHERE EXISTS (SELECT 1 FROM Posts WHERE Tags LIKE '%' || TagName || '%')
AND TagName IS NOT NULL AND TagName != ''
GROUP BY TagName
HAVING COUNT(*) > 0
ORDER BY 2 DESC;