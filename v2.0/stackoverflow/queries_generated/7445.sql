-- {"query": "7445.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1605} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        AVG(p.Score) as AvgPostScore,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Title END, ', ') as QuestionTitles,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Body END, ' | ') as AnswerBodies
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as RankByReputation,
        DENSE_RANK() OVER (ORDER BY BadgeCount DESC) as RankByBadges,
        RANK() OVER (PARTITION BY CASE WHEN Views > 1000 THEN 'High' ELSE 'Low' END ORDER BY UpVotes DESC) as RankByViews
    FROM UserStats
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        COALESCE(p.AcceptedAnswerId, 0) as HasAcceptedAnswer,
        CASE 
            WHEN p.Score > 10 THEN 'High'
            WHEN p.Score > 5 THEN 'Medium'
            ELSE 'Low'
        END as ScoreCategory,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1)
            ELSE 0
        END as TagCount,
        CASE 
            WHEN p.PostTypeId = 1 AND p.Score > 5 AND p.ViewCount > 100 THEN 'Popular Question'
            WHEN p.PostTypeId = 2 AND p.Score > 10 THEN 'High Value Answer'
            WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN 'Viral Question'
            ELSE 'Regular Post'
        END as PostClassification
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01'::timestamp
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Hot Tag'
            WHEN t.Count > 100 THEN 'Popular Tag'
            WHEN t.Count > 10 THEN 'Common Tag'
            ELSE 'Rare Tag'
        END as TagPopularity,
        RANK() OVER (ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
),
MergedAnalysis AS (
    SELECT 
        pu.UserId,
        pu.DisplayName,
        pu.Reputation,
        pu.PostCount,
        pu.BadgeCount,
        pu.LastPostDate,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.PostType,
        pa.ScoreCategory,
        pa.TagCount,
        pa.PostClassification,
        ta.TagName,
        ta.TagCount as TaggedCount,
        ta.TagPopularity,
        CASE 
            WHEN pa.Score > 10 AND pu.Reputation > 5000 THEN 'High Performer'
            WHEN pa.Score > 5 AND pu.BadgeCount > 5 THEN 'Mid Performer'
            WHEN pu.PostCount > 100 THEN 'Active Contributor'
            ELSE 'Regular User'
        END as UserPerformanceSegment
    FROM RankedUsers pu
    INNER JOIN PostAnalysis pa ON pu.UserId = pa.OwnerUserId
    LEFT JOIN TagAnalysis ta ON pa.Tags IS NOT NULL 
        AND POSITION('<' || ta.TagName || '>' IN pa.Tags) > 0
    WHERE pa.ScoreCategory IN ('High', 'Medium')
)
SELECT 
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT UserId) as UniqueUsers,
    COUNT(DISTINCT PostId) as UniquePosts,
    COUNT(DISTINCT TagName) as UniqueTags,
    AVG(Reputation) as AvgReputation,
    AVG(PostCount) as AvgPostCount,
    AVG(BadgeCount) as AvgBadgeCount,
    MAX(LastPostDate) as LatestPostDate,
    MIN(LastPostDate) as EarliestPostDate,
    STRING_AGG(DISTINCT DisplayName, ', ') as AllUserNames,
    STRING_AGG(DISTINCT PostClassification, '; ') as PostClassifications,
    STRING_AGG(DISTINCT TagPopularity, ', ') as TagPopularityLevels,
    STRING_AGG(DISTINCT UserPerformanceSegment, ', ') as UserSegments,
    COUNT(CASE WHEN PostClassification = 'High Value Answer' THEN 1 END) as HighValueAnswers,
    COUNT(CASE WHEN PostClassification = 'Popular Question' THEN 1 END) as PopularQuestions,
    COUNT(CASE WHEN TagPopularity = 'Hot Tag' THEN 1 END) as HotTags,
    COUNT(CASE WHEN UserPerformanceSegment = 'High Performer' THEN 1 END) as HighPerformers,
    COUNT(CASE WHEN UserPerformanceSegment = 'Active Contributor' THEN 1 END) as ActiveContributors
FROM MergedAnalysis ma
WHERE ma.Reputation > 1000
  AND ma.PostCount > 10
  AND (ma.Score > 5 OR ma.ViewCount > 100)
  AND (ma.TagCount > 0 OR ma.TagName IS NOT NULL)
  AND EXISTS (
    SELECT 1 FROM Posts p 
    WHERE p.OwnerUserId = ma.UserId 
      AND p.CreationDate >= '2020-01-01'::timestamp
      AND p.Score > 0
  )
  AND (
    ma.PostClassification IN ('High Value Answer', 'Popular Question', 'Viral Question')
    OR ma.TagPopularity IN ('Hot Tag', 'Popular Tag')
    OR ma.UserPerformanceSegment IN ('High Performer', 'Active Contributor')
  )
  AND COALESCE(ma.TagCount, 0) + COALESCE(ma.TaggedCount, 0) > 1
  AND (
    SELECT COUNT(*) 
    FROM Votes v 
    WHERE v.PostId = ma.PostId 
      AND v.VoteTypeId = 2
  ) > 0
  AND (
    SELECT COUNT(*) 
    FROM Comments c 
    WHERE c.PostId = ma.PostId
  ) BETWEEN 0 AND 50
  AND (
    SELECT COUNT(*) 
    FROM PostHistory ph 
    WHERE ph.PostId = ma.PostId 
      AND ph.PostHistoryTypeId IN (1, 2, 3)
  ) > 0;