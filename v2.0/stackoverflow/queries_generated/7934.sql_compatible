WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as TotalUserPosts,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgUserScore,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevCreationDate
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
        AND p.CreationDate >= TIMESTAMP '2022-01-01 00:00:00'
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT r.Id) as UserPostCount,
        SUM(CASE WHEN r.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN r.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        AVG(r.Score) as AvgScore,
        MAX(r.CreationDate) as LatestActivity,
        STRING_AGG(r.Title, ' | ' ORDER BY r.CreationDate) as RecentTitles,
        CASE 
            WHEN COUNT(r.Id) > 0 AND MAX(r.CreationDate) >= TIMESTAMP '2023-01-01 00:00:00' THEN 'Active'
            WHEN COUNT(r.Id) > 0 THEN 'Inactive'
            ELSE 'New'
        END as UserStatus
    FROM Users u
    LEFT JOIN RankedPosts r ON u.Id = r.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalytics AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%'), 0) as PostsWithTag,
        CASE 
            WHEN t.Count > 100 THEN 'Popular'
            WHEN t.Count > 10 THEN 'Moderate'
            ELSE 'Niche'
        END as TagPopularity,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as AvgScoreForTag
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName != ''
),
PostActivity AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.CreationDate,
        ph.Comment,
        ph.Text,
        CASE 
            WHEN ph.PostHistoryTypeId IN (1, 4, 6) THEN 'Title/Tag Edit'
            WHEN ph.PostHistoryTypeId IN (2, 5) THEN 'Content Edit'
            WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 'State Change'
            ELSE 'Other'
        END as ActivityType,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) as ActivitySequence,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) as PreviousActivityDate
    FROM PostHistory ph
    WHERE ph.CreationDate >= TIMESTAMP '2023-01-01 00:00:00'
        AND ph.PostHistoryTypeId IN (1, 2, 4, 5, 6, 10, 11, 12, 13)
),
FinalAnalysis AS (
    SELECT 
        rs.Id as PostId,
        rs.PostTypeId,
        rs.OwnerUserId,
        rs.Score,
        rs.ViewCount,
        rs.Title,
        rs.Tags,
        rs.AnswerCount,
        rs.CommentCount,
        rs.FavoriteCount,
        rs.UserPostRank,
        rs.TotalUserPosts,
        rs.AvgUserScore,
        rs.PrevScore,
        rs.PrevCreationDate,
        COALESCE(ust.DisplayName, 'Unknown') as OwnerDisplayName,
        ust.Reputation,
        ust.UserStatus,
        ust.UserPostCount,
        ta.TagName,
        ta.TagCount,
        ta.TagPopularity,
        ta.AvgScoreForTag,
        pa.ActivityType,
        pa.ActivitySequence,
        EXTRACT(EPOCH FROM (pa.CreationDate - pa.PreviousActivityDate)) as SecondsSinceLastActivity,
        CASE 
            WHEN rs.PrevScore IS NOT NULL AND rs.PrevScore <> rs.Score THEN
                ROUND(((rs.Score - rs.PrevScore) * 100.0 / NULLIF(rs.PrevScore, 0)), 2)
            ELSE 0 
        END as ScoreChangePercent,
        CASE 
            WHEN rs.Score > 1000 THEN 'HighlyVoted'
            WHEN rs.Score > 100 THEN 'ModeratelyVoted'
            WHEN rs.Score > 0 THEN 'LowVoted'
            ELSE 'NoVotes'
        END as VotingCategory,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rs.Id AND v.VoteTypeId IN (2,3)) as NetVotes,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rs.Id) as CommentCountFinal,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rs.Id AND pl.LinkTypeId = 3) as DuplicateLinks,
        (SELECT STRING_AGG(ph2.Comment, ' | ') FROM PostHistory ph2 WHERE ph2.PostId = rs.Id AND ph2.PostHistoryTypeId = 33) as NoticeComments,
        COALESCE(ust.Reputation, 0) + COALESCE(ust.Views, 0) as CombinedActivityMetric
    FROM RankedPosts rs
    LEFT JOIN UserStats ust ON rs.OwnerUserId = ust.UserId
    LEFT JOIN PostActivity pa ON rs.Id = pa.PostId
    LEFT JOIN TagAnalytics ta ON rs.Tags IS NOT NULL 
        AND (rs.Tags LIKE '%' || ta.TagName || '%' OR rs.Tags LIKE '%' || ta.TagName || '>')
    WHERE rs.UserPostRank <= 5 
        AND rs.Score IS NOT NULL
        AND rs.ViewCount IS NOT NULL
)
SELECT 
    PostId,
    PostTypeId,
    OwnerUserId,
    Score,
    ViewCount,
    Title,
    Tags,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    UserPostRank,
    TotalUserPosts,
    AvgUserScore,
    PrevScore,
    PrevCreationDate,
    OwnerDisplayName,
    Reputation,
    UserStatus,
    UserPostCount,
    TagName,
    TagCount,
    TagPopularity,
    AvgScoreForTag,
    ActivityType,
    ActivitySequence,
    SecondsSinceLastActivity,
    ScoreChangePercent,
    VotingCategory,
    NetVotes,
    CommentCountFinal,
    DuplicateLinks,
    NoticeComments,
    CombinedActivityMetric,
    CASE 
        WHEN CombinedActivityMetric > 1000 AND AvgScoreForTag > 5 THEN 'HighlyActiveTaggedPost'
        WHEN CombinedActivityMetric > 500 AND Score > 10 THEN 'ActivePost'
        WHEN TagPopularity = 'Popular' AND Score > 1 THEN 'PopularPost'
        WHEN Score > 50 THEN 'NotablePost'
        ELSE 'RegularPost'
    END as PostClassification
FROM FinalAnalysis
WHERE Score > 0 
    AND (NOT (PostTypeId = 1 AND AnswerCount > 10) OR AnswerCount IS NULL) 
    AND CombinedActivityMetric > 0
    AND (NOT (TagPopularity = 'Popular' AND TagCount > 500) OR TagCount IS NULL)
ORDER BY CombinedActivityMetric DESC, Score DESC, ViewCount DESC
LIMIT 5000;